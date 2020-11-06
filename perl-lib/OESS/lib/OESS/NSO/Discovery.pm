use strict;
use warnings;

package OESS::NSO::Discovery;

use AnyEvent;
use Data::Dumper;
use GRNOC::RabbitMQ::Method;
use HTTP::Request::Common;
use JSON;
use Log::Log4perl;
use LWP::UserAgent;
use XML::LibXML;

use OESS::Config;
use OESS::DB;
use OESS::DB::Interface;
use OESS::DB::Node;
use OESS::Node;
use OESS::RabbitMQ::Dispatcher;

=head1 OESS::NSO::Discovery

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        config          => undef,
        config_filename => '/etc/oess/database.xml',
        logger          => Log::Log4perl->get_logger('OESS.NSO.Discovery'),
        @_
    };
    my $self = bless $args, $class;

    if (!defined $self->{config}) {
        $self->{config} = new OESS::Config(config_filename => $self->{config_filename});
    }
    $self->{db} = new OESS::DB(config => $self->{config}->filename);
    $self->{nodes} = {};

    $self->{www} = new LWP::UserAgent;
    my $host = $self->{config}->nso_host;
    $host =~ s/http(s){0,1}:\/\///g; # Strip http:// or https:// from string
    $self->{www}->credentials($host, "restconf", $self->{config}->nso_username, $self->{config}->nso_password);

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop;
    };

    return $self;
}

=head2 connection_handler

=cut
sub connection_handler {
    my $self = shift;

    return 1;
}

=head2 device_handler

device_handler queries each devices for basic system info:
- loopback address
- firmware version

=cut
sub device_handler {
    my $self = shift;
    $self->{logger}->info("Calling device_handler.");

    foreach my $key (keys %{$self->{nodes}}) {
        my $node = $self->{nodes}->{$key};

        my $dom = eval {
            my $res = $self->{www}->get($self->{config}->nso_host . "/restconf/data/tailf-ncs:devices/device=$node->{name}");
            return XML::LibXML->load_xml(string => $res->content);
        };
        if ($@) {
            warn 'tailf-ncs:devices:' . $@;
            $self->{logger}->error('tailf-ncs:devices:' . $@);
            next;
        }

        my $data = eval {
            return {
                name          => $dom->findvalue('/ncs:device/ncs:name'),
                platform      => $dom->findvalue('/ncs:device/ncs:platform/ncs:name'),
                version       => $dom->findvalue('/ncs:device/ncs:platform/ncs:version'),
                model         => $dom->findvalue('/ncs:device/ncs:platform/ncs:model'),
                serial_number => $dom->findvalue('/ncs:device/ncs:platform/ncs:serial-number')
            };
        };
        if ($@) {
            warn 'device:' . $@;
            $self->{logger}->error('device:' . $@);
            next;
        }

        $self->{db}->start_transaction;
        my $device = new OESS::Node(db => $self->{db}, name => $data->{name});
        $device->name($data->{name});
        $device->model($data->{model});
        $device->sw_version($data->{version});
        $device->vendor('Cisco') if ($data->{platform} eq 'ios-xr');
        $device->update;
        $self->{db}->commit;
    }
    return 1;
}

=head2 interface_handler

interface_handler queries each device for interface configuration and
operational state.

=cut
sub interface_handler {
    my $self = shift;
    $self->{logger}->info("Calling interface_handler.");

    foreach my $key (keys %{$self->{nodes}}) {
        my $node = $self->{nodes}->{$key};

        my $dom = eval {
            my $res = $self->{www}->get($self->{config}->nso_host . "/restconf/data/tailf-ncs:devices/device=$node->{name}/config/tailf-ned-cisco-ios-xr:interface");
            return XML::LibXML->load_xml(string => $res->content);
        };
        if ($@) {
            # Don't log Empty String error as there are simply no interfaces
            if ($@ !~ /Empty String/g) {
                warn 'tailf-ned-cisco-ios-xr:interface:' . $@;
                $self->{logger}->error('tailf-ned-cisco-ios-xr:interface:' . $@);
            }
            next;
        }

        my $ports = eval {
            my $result = [];

            my @gb_ports = $dom->findnodes('/cisco-ios-xr:interface/cisco-ios-xr:GigabitEthernet');
            foreach my $port (@gb_ports) {
                my $port_info = {
                    admin_state => $port->exists('./cisco-ios-xr:shutdown') ? 'down' : 'up',
                    bandwidth   => $port->findvalue('./cisco-ios-xr:speed') || 1000,
                    description => $port->findvalue('./cisco-ios-xr:description') || '',
                    mtu         => $port->findvalue('./cisco-ios-xr:mtu') || 0,
                    name        => $port->findvalue('./cisco-ios-xr:id')
                };
                push @$result, $port_info;
            }
            return $result;
        };
        if ($@) {
            warn 'port_info:' . $@;
            $self->{logger}->error('port_info:' . $@);
            next;
        }

        # TODO save nso queried data into db
        warn 'ports: ' . Dumper($ports);
    }
    return 1;
}

=head2 link_handler

=cut
sub link_handler {
    my $self = shift;

    return 1;
}

=head2 new_switch

=cut
sub new_switch {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    my $node = OESS::DB::Node::fetch(db => $self->{db}, node_id => $params->{node_id}{value});
    if (!defined $node) {
        my $err = "Couldn't lookup node $params->{node_id}{value}. Discovery will not properly complete on this node.";
        $self->{logger}->error($err);
        &$error($err);
    }
    $self->{nodes}->{$params->{node_id}{value}} = $node;

    warn "Switch $node->{name} registered with discovery.";
    $self->{logger}->info("Switch $node->{name} registered with discovery.");

    $self->device_handler;
    $self->interface_handler;

    return &$success({ status => 1 });
}

=head2 start

=cut
sub start {
    my $self = shift;

    # Load devices from database
    my $nodes = OESS::DB::Node::fetch_all(db => $self->{db});
    if (!defined $nodes) {
        warn "Couldn't lookup nodes. Discovery will not collect data on any existing nodes.";
        $self->{logger}->error("Couldn't lookup nodes. Discovery will not collect data on any existing nodes.");
    }
    foreach my $node (@$nodes) {
        $self->{nodes}->{$node->{node_id}} = $node;
    }

    # Setup polling subroutines
    $self->{connection_timer} = AnyEvent->timer(
        after    => 20,
        interval => 60,
        cb       => sub { $self->connection_handler(@_); }
    );
    $self->{device_timer} = AnyEvent->timer(
        after    => 10,
        interval => 60,
        cb       => sub { $self->device_handler(@_); }
    );
    $self->{interface_timer} = AnyEvent->timer(
        after    =>  60,
        interval => 120,
        cb       => sub { $self->interface_handler(@_); }
    );
    $self->{link_timer} = AnyEvent->timer(
        after    =>  80,
        interval => 120,
        cb       => sub { $self->link_handler(@_); }
    );

    $self->{dispatcher} = new OESS::RabbitMQ::Dispatcher(
        # queue => 'oess-discovery',
        # topic => 'oess.discovery.rpc'
        queue => 'MPLS-Discovery',
        topic => 'MPLS.Discovery.RPC'
    );

    my $new_switch = new GRNOC::RabbitMQ::Method(
        name        => 'new_switch',
        description => 'Add a new switch to the database',
        async       => 1,
        callback    => sub { $self->new_switch(@_); }
    );
    $new_switch->add_input_parameter(
        name        => 'node_id',
        description => 'Id of the new node',
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::NUMBER_ID
    );
    $self->{dispatcher}->register_method($new_switch);

    my $is_online = new GRNOC::RabbitMQ::Method(
        name        => "is_online",
        description => 'Return if this service is online',
        async       => 1,
        callback    => sub {
            my $method = shift;
            return $method->{success_callback}({ successful => 1 });
        }
    );
    $self->{dispatcher}->register_method($is_online);

    $self->{dispatcher}->start_consuming;
    return 1;
}

=head2 stop

=cut
sub stop {
    my $self = shift;
    $self->{logger}->info('Stopping OESS::NSO::Discovery.');
    $self->{dispatcher}->stop_consuming;
}

1;
