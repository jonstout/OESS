package OESS::NSO::FWDCTL;

use AnyEvent;
use Data::Dumper;
use GRNOC::RabbitMQ::Method;
use GRNOC::WebService::Regex;
use HTTP::Request::Common;
use JSON;
use Log::Log4perl;
use LWP::UserAgent;
use XML::LibXML;

use OESS::Config;
use OESS::DB;
use OESS::DB::Node;
use OESS::L2Circuit;
use OESS::Node;
use OESS::NSO::Client;
use OESS::RabbitMQ::Dispatcher;
use OESS::VRF;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant FWDCTL_BLOCKED     => 4;

use constant PENDING_DIFF_NONE  => 0;
use constant PENDING_DIFF       => 1;
use constant PENDING_DIFF_ERROR => 2;
use constant PENDING_DIFF_APPROVED => 3;

=head1 OESS::NSO::FWDCTL

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        connection_cache => undef, # OESS::NSO::ConnectionCache
        db    => undef, # OESS::DB
        nso   => undef, # OESS::NSO::Client or OESS::NSO::ClientStub
        logger          => Log::Log4perl->get_logger('OESS.NSO.FWDCTL'),
        @_
    };
    my $self = bless $args, $class;

    if (!defined $self->{config_obj}) {
        $self->{config_obj} = new OESS::Config(config_filename => $self->{config_filename});
    }

    $self->{cache} = {};
    $self->{l3_cache} = {};
    $self->{flat_cache} = {};
    $self->{l3_flat_cache} = {};

    $self->{pending_diff} = {};
    $self->{nodes} = {};

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop;
    };

    return $self;
}

=head2 addVlan

=cut
sub addVlan {
    my $self = shift;
    my $args = {
        circuit_id => undef,
        @_
    };

    my $conn = new OESS::L2Circuit(
        db => $self->{db},
        circuit_id => $args->{circuit_id}
    );
    $conn->load_endpoints;

    my $err = $self->{nso}->create_l2connection($conn);
    return $err if (defined $err);

    $self->{connection_cache}->add_connection($conn, 'l2');
    return;
}

=head2 deleteVlan

=cut
sub deleteVlan {
    my $self   = shift;
    my $args = {
        circuit_id => undef,
        @_
    };

    my $conn = new OESS::L2Circuit(
        db => $self->{db},
        circuit_id => $args->{circuit_id}
    );
    $conn->load_endpoints;

    my $err = $self->{nso}->delete_l2connection($args->{circuit_id});
    return $err if (defined $err);

    $self->{connection_cache}->remove_connection($conn, 'l2');
    return;
}

=head2 modifyVlan

=cut
sub modifyVlan {
    my $self = shift;
    my $args = {
        pending => undef,
        @_
    };

    my $pending_hash = decode_json($args->{pending});
    my $pending_conn = new OESS::L2Circuit(db => $self->{db}, model => $pending_hash);

    my $err = $self->{nso}->edit_l2connection($pending_conn);
    return $err if (defined $err);

    $self->{connection_cache}->add_connection($conn, 'l2');
    return;
}

=head2 addVrf

=cut
sub addVrf {
    my $self = shift;
    my $args = {
        vrf_id => undef,
        @_
    };

    my $conn = new OESS::VRF(
        db     => $self->{db},
        vrf_id => $args->{vrf_id}
    );
    $conn->load_endpoints;

    foreach my $ep (@{$conn->endpoints}) {
        $ep->load_peers;
    }

    my $err = $self->{nso}->create_l3connection($conn);
    return $err if (defined $err);

    $self->{connection_cache}->add_connection($conn, 'l3');
    return;
}

=head2 deleteVrf

=cut
sub deleteVrf {
    my $self   = shift;
    my $args = {
        vrf_id => undef,
        @_
    };

    my $conn = new OESS::VRF(
        db => $self->{db},
        vrf_id => $args->{vrf_id}
    );
    $conn->load_endpoints;

    my $err = $self->{nso}->delete_l3connection($args->{vrf_id});
    return $err if (defined $err);

    $self->{connection_cache}->remove_connection($conn, 'l3');
    return;
}

=head2 modifyVrf

=cut
sub modifyVrf {
    my $self   = shift;
    my $args = {
        pending => undef,
        @_
    };

    my $pending_hash = decode_json($args->{pending});
    my $pending_conn = new OESS::VRF(db => $self->{db}, model => $pending_hash);

    my $err = $self->{nso}->edit_l3connection($pending_conn);
    return $err if (defined $err);

    $self->{connection_cache}->add_connection($conn, 'l3');
    return;
}

=head2 diff

diff reads all connections from cache, loads all connections from nso,
determines if a configuration change within nso is required, and if so, make
the change.

In the case of a large change (effects > N connections), the diff is put
into a pending state. Diff states are tracked on a per-node basis.

=cut
sub diff {
    my $self = shift;

    my ($connections, $err) = $self->{nso}->get_l2connections();
    if (defined $err) {
        $self->{logger}->error($err);
        return;
    }

    # After a connection has been sync'd to NSO we remove it from our hash of
    # nso connections. Any connections left in this hash after syncing are not
    # known by OESS and should be removed.
    my $nso_l2connections = {};
    foreach my $conn (@{$connections}) {
        $nso_l2connections->{$conn->{connection_id}} = $conn;
    }

    my $network_diff = {};
    my $changes = [];

    # Connections are stored in-memory multiple times under each node they're
    # associed with. Keep a record of connections as they're sync'd to prevent a
    # connection from being sync'd more than once.
    my $syncd_connections = {};

    # Needed to ensure diff state may be set to pending_diff_none after approval
    foreach my $node_id (keys %{$self->{cache}}) {
        # TODO Cleanup this hacky lookup
        my $node_obj = new OESS::Node(db => $self->{db}, node_id => $node_id);
        $network_diff->{$node_obj->name} = "";
    }

    foreach my $node_id (keys %{$self->{cache}}) {
        foreach my $conn_id (keys %{$self->{cache}->{$node_id}}) {

            # Skip connections if they're already sync'd.
            next if defined $syncd_connections->{$conn_id};
            $syncd_connections->{$conn_id} = 1;

            # Compare cached connection against NSO connection. If no difference
            # continue with next connection, otherwise update NSO to align with
            # cache.
            my $conn = $self->{cache}->{$node_id}->{$conn_id};
            my $diff_required = 0;

            my $diff = $self->_nso_connection_diff($conn, $nso_l2connections->{$conn_id});
            foreach my $node (keys %$diff) {
                next if $diff->{$node} eq "";

                $diff_required = 1;
                $network_diff->{$node} .= $diff->{$node};
            }

            push(@$changes, { type => 'edit-l2connection', value => $conn }) if $diff_required;
            delete $nso_l2connections->{$conn_id};
        }
    }

    foreach my $conn_id (keys %{$nso_l2connections}) {
        # TODO Generate conn removal diff data and add to node diffs
        my $diff = $self->_nso_connection_diff(undef, $nso_l2connections->{$conn_id});
        foreach my $node (keys %$diff) {
            next if $diff->{$node} eq "";

            $diff_required = 1;
            $network_diff->{$node} .= $diff->{$node};
        }

        push @$changes, { type => 'delete-l2connection', value => $nso_l2connections->{$conn_id} };
    }
    warn 'Network diff:' . Dumper($network_diff);

    # If the database asserts there is no diff pending but memory disagrees,
    # then the pending state was modified by an admin. The pending diff may now
    # proceed.
    foreach my $node_name (keys %$network_diff) {
        my $node = new OESS::Node(db => $self->{db}, name => $node_name);
        warn "Diffing $node_name.";

        if (length $network_diff->{$node_name} < 30) {
            warn "Diff approved for $node_name";

            $self->{pending_diff}->{$node_name} = PENDING_DIFF_NONE;
            $node->pending_diff(PENDING_DIFF_NONE);
            $node->update;
        } else {
            if ($self->{pending_diff}->{$node_name} == PENDING_DIFF_NONE) {
                warn "Diff requires manual approval.";

                $self->{pending_diff}->{$node_name} = PENDING_DIFF;
                $node->pending_diff(PENDING_DIFF);
                $node->update;
            }

            if ($self->{pending_diff}->{$node_name} == PENDING_DIFF && $node->pending_diff == PENDING_DIFF_NONE) {
                warn "Diff manually approved.";
                $self->{pending_diff}->{$node_name} = PENDING_DIFF_APPROVED;
            }
        }
    }

    foreach my $change (@$changes) {
        if ($change->{type} eq 'edit-l2connection') {
            my $conn = $change->{value};

            # If conn endpoint on node with a blocked diff skip
            my $diff_approval_required = 0;
            foreach my $ep (@{$conn->endpoints}) {
                if ($self->{pending_diff}->{$ep->node} == PENDING_DIFF) {
                    $diff_approval_required =  1;
                    last;
                }
            }
            if ($diff_approval_required) {
                warn "Not syncing l2connection $change->{value}.";
                next;
            }

            my $err = $self->{nso}->edit_l2connection($conn);
            if (defined $err) {
                $self->{logger}->error($err);
                warn $err;
            }
        }
        elsif ($change->{type} eq 'delete-l2connection') {
            my $conn = $change->{value};

            # If conn endpoint on node with a blocked diff skip
            my $diff_approval_required = 0;
            foreach my $ep (@{$conn->{endpoint}}) {
                if ($self->{pending_diff}->{$ep->{device}} == PENDING_DIFF) {
                    $diff_approval_required =  1;
                    last;
                }
            }
            if ($diff_approval_required) {
                warn "Not syncing l2connection $conn->{connection_id}.";
                next;
            }

            my $err = $self->{nso}->delete_l2connection($conn->{connection_id});
            if (defined $err) {
                $self->{logger}->error($err);
            }
        }
        else {
            warn 'no idea what happened here';
        }
    }


    return 1;
}

=head2 get_diff_text

=cut
sub get_diff_text {
    my $self = shift;
    my $args = {
        node_id   => undef,
        node_name => undef,
        @_
    };

    my $node_id = $args->{node_id};
    my $node_name = "";

    my ($connections, $err) = $self->{nso}->get_l2connections();
    if (defined $err) {
        $self->{logger}->error($err);
        return;
    }

    # After a connection has been sync'd to NSO we remove it from our hash of
    # nso connections. Any connections left in this hash after syncing are not
    # known by OESS and should be removed.
    my $nso_l2connections = {};
    foreach my $conn (@{$connections}) {
        $nso_l2connections->{$conn->{connection_id}} = $conn;
    }

    my $network_diff = {};
    my $changes = [];

    # Connections are stored in-memory multiple times under each node they're
    # associed with. Keep a record of connections as they're sync'd to prevent a
    # connection from being sync'd more than once.
    my $syncd_connections = {};

    # Needed to ensure diff state may be set to pending_diff_none after approval
    foreach my $key (@{$self->{connection_cache}->get_included_nodes}) {
        # TODO Cleanup this hacky lookup
        my $node_obj = new OESS::Node(db => $self->{db}, node_id => $key);
        $network_diff->{$node_obj->name} = "";
        if ($key == $node_id) {
            $node_name = $node_obj->name;
        }
    }

    foreach my $node_id (@{$self->{connection_cache}->get_included_nodes}) {
        foreach my $conn (@{$self->{connection_cache}->get_connections_by_node($node_id, 'l2')}) {

            # Skip connections if they're already sync'd.
            next if defined $syncd_connections->{$conn->circuit_id};
            $syncd_connections->{$conn->circuit_id} = 1;

            # Compare cached connection against NSO connection. If no difference
            # continue with next connection, otherwise update NSO to align with
            # cache.
            my $diff_required = 0;

            my $diff = $self->_nso_connection_diff($conn, $nso_l2connections->{$conn->circuit_id});
            foreach my $node (keys %$diff) {
                next if $diff->{$node} eq "";

                $diff_required = 1;
                $network_diff->{$node} .= $diff->{$node};
            }

            push(@$changes, { type => 'edit-l2connection', value => $conn->circuit_id }) if $diff_required;
            delete $nso_l2connections->{$conn->circuit_id};
        }
    }

    foreach my $conn_id (keys %{$nso_l2connections}) {
        my $diff = $self->_nso_connection_diff(undef, $nso_l2connections->{$conn_id});
        foreach my $node (keys %$diff) {
            next if $diff->{$node} eq "";

            $diff_required = 1;
            $network_diff->{$node} .= $diff->{$node};
        }

        push @$changes, { type => 'delete-l2connection', value => $conn_id };
    }

    if (defined $args->{node_name}) {
        $node_name = $args->{node_name};
    }
    warn 'Network diff:' . Dumper($network_diff);
    warn Dumper($network_diff->{$node_name});

    return $network_diff->{$node_name};
}

=head2 new_switch

=cut
sub new_switch {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    if (defined $self->{nodes}->{$params->{node_id}{value}}) {
        $self->{logger}->warn("Node $params->{node_id}{value} already registered with FWDCTL.");
        return &$success({ status => 1 });
    }

    my $node = OESS::DB::Node::fetch(db => $self->{db}, node_id => $params->{node_id}{value});
    if (!defined $node) {
        my $err = "Couldn't lookup node $params->{node_id}{value}. FWDCTL will not properly provision on this node.";
        $self->{logger}->error($err);
        return &$error($err);
    }
    $self->{nodes}->{$params->{node_id}{value}} = $node;

    warn "Switch $node->{name} registered with FWDCTL.";
    $self->{logger}->info("Switch $node->{name} registered with FWDCTL.");

    # Make first invocation of polling subroutines
    $self->diff;

    return &$success({ status => 1 });
}

=head2 update_cache

update_cache reads all connections from the database and loads them
into an in-memory cache.

=cut
sub update_cache {
    my $self   = shift;

    my $l2connections = OESS::DB::Circuit::fetch_circuits(
        db => $self->{db}
    );
    if (!defined $l2connections) {
        $self->{logger}->error("Couldn't load l2connections in update_cache.");
        return "Couldn't load l2connections in update_cache.";
    }

    foreach my $conn (@$l2connections) {
        my $obj = new OESS::L2Circuit(db => $self->{db}, model => $conn);
        $obj->load_endpoints;
        $self->{connection_cache}->add_connection($obj, 'l2');
    }

    # TODO lookup and populate l3connections

    return;
}

=head2 _nso_connection_equal_to_cached

_nso_connection_equal_to_cached compares the NSO provided data structure against
the cached connection object. If there is no difference return 1, otherwise
return 0.

NSO L2Connection:

    {
        'connection_id' => 3000,
        'directly-modified' => {
            'services' => [
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'0\'][sdp:name=\'3000\']',
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'1\'][sdp:name=\'3000\']'
            ],
            'devices' => [
                'xr0'
            ]
        },
        'endpoint' => [
            {
                'bandwidth' => 0,
                'endpoint_id' => 1,
                'interface' => 'GigabitEthernet0/0',
                'tag' => 1,
                'device' => 'xr0'
            },
            {
                'bandwidth' => 0,
                'endpoint_id' => 2,
                'interface' => 'GigabitEthernet0/1',
                'tag' => 1,
                'device' => 'xr0'
            }
        ],
        'device-list' => [
            'xr0'
        ],
        'modified' => {
            'services' => [
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'1\'][sdp:name=\'3000\']',
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'0\'][sdp:name=\'3000\']'
            ],
            'devices' => [
                'xr0'
            ]
        }
    }

=cut
sub _nso_connection_equal_to_cached {
    my $self = shift;
    my $conn = shift;
    my $nsoc = shift; # NSOConnection

    my $conn_ep_count = @{$conn->endpoints};
    my $nsoc_ep_count = @{$nsoc->{endpoint}};
    if (@{$conn->endpoints} != @{$nsoc->{endpoint}}) {
        warn "ep count wrong";
        return 0;
    }

    my $ep_index = {};
    foreach my $ep (@{$conn->endpoints}) {
        if (!defined $ep_index->{$ep->node}) {
            $ep_index->{$ep->node} = {};
        }
        $ep_index->{$ep->node}->{$ep->interface} = $ep;
    }

    foreach my $ep (@{$nsoc->{endpoint}}) {
        if (!defined $ep_index->{$ep->{device}}->{$ep->{interface}}) {
            warn "ep not in cache";
            return 0;
        }
        my $ref_ep = $ep_index->{$ep->{device}}->{$ep->{interface}};

        warn "band" if $ep->{bandwidth} != $ref_ep->bandwidth;
        warn "tag" if $ep->{tag} != $ref_ep->tag;
        warn "inner_tag" if $ep->{inner_tag} != $ref_ep->inner_tag;

        # Compare endpoints
        return 0 if $ep->{bandwidth} != $ref_ep->bandwidth;
        return 0 if $ep->{tag} != $ref_ep->tag;
        return 0 if $ep->{inner_tag} != $ref_ep->inner_tag;

        delete $ep_index->{$ep->{device}}->{$ep->{interface}};
    }

    foreach my $key (keys %{$ep_index}) {
        my @leftovers = keys %{$ep_index->{$key}};
        warn "leftover eps: ".Dumper(@leftovers) if @leftovers > 0;
        return 0 if @leftovers > 0;
    }

    return 1;
}

=head2 _nso_connection_diff

_nso_connection_diff compares the NSO provided data structure against the cached
connection object. Returns a hash of device-name to textual representation of
the diff.

If $conn is undef, _nso_connection_diff will generate a diff indicating that all
endpoints of $nsoc will be removed.

NSO L2Connection:

    {
        'connection_id' => 3000,
        'directly-modified' => {
            'services' => [
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'0\'][sdp:name=\'3000\']',
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'1\'][sdp:name=\'3000\']'
            ],
            'devices' => [
                'xr0'
            ]
        },
        'endpoint' => [
            {
                'bandwidth' => 0,
                'endpoint_id' => 1,
                'interface' => 'GigabitEthernet0/0',
                'tag' => 1,
                'device' => 'xr0'
            },
            {
                'bandwidth' => 0,
                'endpoint_id' => 2,
                'interface' => 'GigabitEthernet0/1',
                'tag' => 1,
                'device' => 'xr0'
            }
        ],
        'device-list' => [
            'xr0'
        ],
        'modified' => {
            'services' => [
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'1\'][sdp:name=\'3000\']',
                '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'0\'][sdp:name=\'3000\']'
            ],
            'devices' => [
                'xr0'
            ]
        }
    }

=cut
sub _nso_connection_diff {
    my $self = shift;
    my $conn = shift;
    my $nsoc = shift; # NSOConnection

    my $diff = {};
    my $ep_index = {};

    if (!defined $conn) {
        foreach my $ep (@{$nsoc->{endpoint}}) {
            $diff->{$ep->{device}} = "" if !defined $diff->{$ep->{device}};
            $diff->{$ep->{device}} .= "- $ep->{interface}\n";
            $diff->{$ep->{device}} .= "-   Bandwidth: $ep->{bandwidth}\n";
            $diff->{$ep->{device}} .= "-   Tag:       $ep->{tag}\n";
            $diff->{$ep->{device}} .= "-   Inner Tag: $ep->{inner_tag}\n" if defined $ep->{inner_tag};
            next;
        }
        return $diff;
    }

    foreach my $ep (@{$conn->endpoints}) {
        if (!defined $ep_index->{$ep->node}) {
            $diff->{$ep->node} = "";
            $ep_index->{$ep->node} = {};
        }
        $ep_index->{$ep->node}->{$ep->interface} = $ep;
    }

    foreach my $ep (@{$nsoc->{endpoint}}) {
        if (!defined $ep_index->{$ep->{device}}->{$ep->{interface}}) {
            $diff->{$ep->{device}} = "" if !defined $diff->{$ep->{device}};
            $diff->{$ep->{device}} .= "- $ep->{interface}\n";
            $diff->{$ep->{device}} .= "-   Bandwidth: $ep->{bandwidth}\n";
            $diff->{$ep->{device}} .= "-   Tag:       $ep->{tag}\n";
            $diff->{$ep->{device}} .= "-   Inner Tag: $ep->{inner_tag}\n" if defined $ep->{inner_tag};
            next;
        }
        my $ref_ep = $ep_index->{$ep->{device}}->{$ep->{interface}};

        # Compare endpoints
        my $ok = 1;
        $ok = 0 if $ep->{bandwidth} != $ref_ep->bandwidth;
        $ok = 0 if $ep->{tag} != $ref_ep->tag;
        $ok = 0 if $ep->{inner_tag} != $ref_ep->inner_tag;
        if (!$ok) {
            $diff->{$ep->{device}} = "" if !defined $diff->{$ep->{device}};
            $diff->{$ep->{device}} .= "  $ep->{interface}\n";
        }

        if ($ep->{bandwidth} != $ref_ep->bandwidth) {
            $diff->{$ep->{device}} .= "-   Bandwidth: $ep->{bandwidth}\n";
            $diff->{$ep->{device}} .= "+   Bandwidth: $ref_ep->{bandwidth}\n";
        }
        if ($ep->{tag} != $ref_ep->tag) {
            $diff->{$ep->{device}} .= "-   Tag:       $ep->{tag}\n";
            $diff->{$ep->{device}} .= "+   Tag:       $ref_ep->{tag}\n";
        }
        if ($ep->{inner_tag} != $ref_ep->inner_tag) {
            $diff->{$ep->{device}} .= "-   Inner Tag: $ep->{inner_tag}\n" if defined $ep->{inner_tag};
            $diff->{$ep->{device}} .= "+   Inner Tag: $ref_ep->{inner_tag}\n" if defined $ref_ep->{inner_tag};
        }

        delete $ep_index->{$ep->{device}}->{$ep->{interface}};
    }

    foreach my $device_key (keys %{$ep_index}) {
        foreach my $ep_key (keys %{$ep_index->{$device_key}}) {
            my $ep = $ep_index->{$device_key}->{$ep_key};
            $diff->{$ep->node} = "" if !defined $diff->{$ep->node};

            $diff->{$ep->node} .= "+ $ep->{interface}\n";
            $diff->{$ep->node} .= "+   Bandwidth: $ep->{bandwidth}\n";
            $diff->{$ep->node} .= "+   Tag:       $ep->{tag}\n";
            $diff->{$ep->node} .= "+   Inner Tag: $ep->{inner_tag}\n" if defined $ep->{inner_tag};
        }
    }

    return $diff;
}

1;
