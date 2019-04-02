package OESS::L2CCC;

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl;
use XML::LibXML;

use OESS::DB;
use OESS::Endpoint;
use OESS::Path;

use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;


=head1 OESS::L2CCC

    use OESS::L2CCC;

    my $l2ccc = OESS::L2CCC->new;

    $l2ccc->save($db); # Save $l2ccc->id to database
    $l2ccc->load($db); # Read $l2ccc->id from database

This package provides an object for quickly creating an L2CCC type
circuit from a json model. Ideally this model would be passed directly
from the web api.

=cut

=head2 new

    my $l2ccc = OESS::L2CCC->new(
      name        => 'my l2ccc',
      description => 'purpose is an example',
      endpoints   => [
        OESS::Endpoint,
        OESS::Endpoint
      ],
      schedule => {
        create => 'now',
        remove => '24h',
      },
      path         => OESS::Path,
      primary_path => OESS::Path
    );

=cut
sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        log => Log::Log4perl->get_logger("OESS.L2CCC"),
        @_
    };

    bless $self, $class;
    return $self;
}


=head2 id

=cut
sub id {
    my $self = shift;
    return $self->{id};
}

=head2 name

=cut
sub name {
    my $self = shift;
    my $name = shift;
    if (defined $name) { $self->{name} = $name; }
    return $self->{name};
}

=head2 description

=cut
sub description {
    my $self = shift;
    my $description = shift;
    if (defined $description) { $self->{description} = $description; }
    return $self->{description};
}

=head2 create_on

=cut
sub create_on {
    my $self = shift;
    my $create_on = shift;
    if (defined $create_on) { $self->{schedule}->{create_on} = $create_on; }
    return $self->{create_on};
}

=head2 remove_on

=cut
sub remove_on {
    my $self = shift;
    my $remove_on = shift;
    if (defined $remove_on) { $self->{schedule}->{remove_on} = $remove_on; }
    return $self->{remove_on};
}

=head2 endpoints

=cut
sub endpoints {
    my $self = shift;
    my $endpoints = shift;
    if (defined $endpoints) { $self->{endpoints} = $endpoints; }
    return $self->{endpoints};
}

=head2 path

=cut
sub path {
    my $self = shift;
    my $path = shift;
    if (defined $path) { $self->{path} = $path; }
    return $self->{path};
}

=head2 primary_path

=cut
sub primary_path {
    my $self = shift;
    my $primary_path = shift;
    if (defined $primary_path) { $self->{primary_path} = $primary_path; }
    return $self->{primary_path};
}

=head2 load

    my $err = $l2ccc->load($db);

=cut
sub load {
    my $self = shift;
    my $db = shift;

    my $data = $db->get_circuit_details(circuit_id => $self->{id});
    if (!defined $data) {
        return "Couldn't load circuit $self->{id} from database.";
    }

    my $err = undef;

    $self->{id} = $data->{circuit_id};

    $self->{path} = OESS::Path->new(id => $data->{path_id});
    $err = $self->{path}->load($db);
    if (defined $err) { return $err; }

    $self->{primary_path} = OESS::Path->new(id => $data->{paths}->{primary}->{path_id});
    $err = $self->{primary_path}->load($db);
    if (defined $err) { return $err; }

    my $db2 = OESS::DB->new(config => '/etc/oess/database.xml');
    foreach my $endpoint (@{$data->{endpoints}}) {
warn Dumper($endpoint);
        my $endpoint = OESS::Endpoint->new(
            model => {
                node => $endpoint->{node},
                interface => $endpoint->{interface}
            },
            db => $db2
        );
#        $err = $endpoint->load($db);
#        if (defined $err) { return $err; }

        push @{$self->{endpoints}}, $endpoint;
    }

    return undef;
}

=head2 _compare_links

_compare_links returns C<1> if all C<$a_links> are in C<$z_links>;
Otherwise it returns 0.

=cut
sub _compare_links{
    my $a_links = shift;
    my $z_links = shift;

    if (@$a_links != @$z_links) {
        return 0;
    }

    my $lookup = {};
    foreach my $l (@$a_links) {
        $lookup->{$l} = 1;
    }

    foreach my $l (@$z_links) {
        if (!defined $lookup->{$l}) {
            return 0;
        }
        $lookup->{$l} = undef;
    }

    return (keys %$lookup > 0) ? 0 : 1;
}

=head2 append_configure

    my $dom = $l2ccc->append_configure(
      XML::LibXML::Document->new('1.0', 'UTF-8'),
      123
    );

=cut
sub append_configure {
    my $self = shift;
    my $dom = shift;
    my $src = shift; # node_id of the device to install.

    if (!defined $dom) {
        $dom = XML::LibXML::Document->new('1.0', 'UTF-8');
    }

    # configuration
    my ($config) = $dom->documentElement();
    if (!defined $config) {
        $config = $dom->createElement('configuration');
        $dom->setDocumentElement($config);
    }

    # configuration > interfaces
    my ($interfaces) = $config->getChildrenByTagName('interfaces');
    if (!defined $interfaces) {
        $interfaces = $dom->createElement('interfaces');
        $config->appendChild($interfaces);
    }

    foreach my $endpoint (@{$self->{endpoints}}) {
        # TODO Check if interface tag with $endpoint->name already
        # exists. If so just add the unit to that tag.

        my $interface = $dom->createElement('interface');
        $interfaces->appendChild($interface);

        my $name = $dom->createElement('name');
        $name->appendText($endpoint->interface->name);
        $interface->appendChild($name);

        my $unit = $dom->createElement('unit');
        $interface->appendChild($unit);

        my $unit_name = $dom->createElement('name');
warn Dumper($endpoint->tag);
        $unit_name->appendText($endpoint->tag);
        $unit->appendChild($unit_name);

        my $description = $dom->createElement('description');
        $description->appendText("OESS-L2CCC-$self->{id}");
        $unit->appendChild($description);

        my $encapsulation = $dom->createElement('encapsulation');
        $encapsulation->appendText("vlan-ccc");
        $unit->appendChild($encapsulation);

        if (defined $endpoint->inner_tag) {
            my $tags = $dom->createElement('vlan-tags');

            my $outer = $dom->createElement('outer');
            $outer->appendText($endpoint->tag);
            $tags->appendChild($outer);

            my $inner = $dom->createElement('inner');
            $inner->appendText($endpoint->inner_tag);
            $tags->appendChild($inner);

            $unit->appendChild($tags);
        } else {
            my $vlan = $dom->createElement('vlan-id');
            $vlan->appendText($endpoint->tag);

            $unit->appendChild($vlan);
        }

        my $output_vlan_map = $dom->createElement('output-vlan-map');
        $unit->appendChild($output_vlan_map);

        my $swap = $dom->createElement('swap');
        $output_vlan_map->appendChild($swap);
    }

    # configuration > protocols
    my ($protocols) = $config->getChildrenByTagName('protocols');
    if (!defined $protocols) {
        $protocols = $dom->createElement('protocols');
        $config->appendChild($protocols);
    }

    # configuration > protocols > mpls
    my ($mpls) = $protocols->getChildrenByTagName('mpls');
    if (!defined $mpls) {
        $mpls = $dom->createElement('mpls');
        $protocols->appendChild($mpls);
    }

    # configuration > protocols > mpls > label-switched-path
    my ($lsp) = $protocols->getChildrenByTagName('label-switched-path');
    if (!defined $lsp) {
        $lsp = $dom->createElement('label-switched-path');
        $mpls->appendChild($lsp);
    }

    # configuration > protocols > mpls > path
    my $path = $dom->createElement('path');
    $mpls->appendChild($path);

    my $path_name = $dom->createElement('name');
    $path_name->appendText("OESS-L2CCC-$self->{id}-SECONDARY");
    $path->appendChild($path_name);

    my $primary_path = $dom->createElement('path');
    $mpls->appendChild($primary_path);

    my $primary_path_name = $dom->createElement('name');
    $primary_path_name->appendText("OESS-L2CCC-$self->{id}-PRIMARY");
    $primary_path->appendChild($primary_path_name);

    # configuration > protocols > mpls > path > path-list
    my $path_list = $dom->createElement('path-list');
    $primary_path->appendChild($path_list);

    my $strict = $dom->createElement('strict');
    $path_list->appendChild($strict);

    foreach my $ip (@{$self->primary_path->hops('172.16.0.7', '172.16.0.6')}) {
        my $name = $dom->createElement('name');
        $name->appendText($ip);
        $path_list->appendChild($name);
    }

    # configuration > protocols > connections
    my ($connections) = $protocols->getChildrenByTagName('connections');
    if (!defined $connections) {
        $connections = $dom->createElement('connections');
        $protocols->appendChild($connections);
    }

    # configuration > protocols > connections > remote-interface-switch
    my ($remote_interface_switch) = $connections->getChildrenByTagName('remote-interface-switch');
    if (!defined $remote_interface_switch) {
        $remote_interface_switch = $dom->createElement('remote-interface-switch');
        $connections->appendChild($remote_interface_switch);
    }

    my $name = $dom->createElement('name');
    $name->appendText("OESS-L2CCC-$self->{id}");
    $remote_interface_switch->appendChild($name);

    foreach my $endpoint (@{$self->{endpoints}}) {
        # TODO Check if interface tag with $endpoint->name already
        # exists. If so just add the unit to that tag.

        my $interface = $dom->createElement('interface');
        $interface->appendText("$endpoint->{name}.$endpoint->{unit}");
        $remote_interface_switch->appendChild($interface);
    }

    my $transmit = $dom->createElement('transmit');
    $transmit->appendText("OESS-L2CCC-$self->{id}");
    $remote_interface_switch->appendChild($transmit);

    my $receive = $dom->createElement('receive');
    $receive->appendText("OESS-L2CCC-$self->{id}");
    $remote_interface_switch->appendChild($receive);

    return $dom
}

=head2 append_unconfigure

=cut
sub append_unconfigure {
    my $self = shift;
    my $conf = shift;

}


1;
