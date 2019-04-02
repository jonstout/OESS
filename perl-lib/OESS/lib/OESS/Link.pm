package OESS::Link;

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl;

use OESS::DB;


=head1 OESS::Link

    use OESS::Link;

    my $link = OESS::Link->new;

    $link->save($db); # Save $link->id to database
    $link->load($db); # Read $link->id from database

This package provides an object for quickly creating a Link from a
json model. Ideally this model would be passed directly from the web
api.

=cut

=head2 new

    my $link = OESS::Link->new(
      {
        id => 7,
        name => '',
        remote_urn => '',
        status => 'active',
        metric => 1,
        in_maintenance => 0,
        interface_a => 7,
        interface_z => 8,
        ip_a => '',
        ip_z => ''
      }
    );

=cut
sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        log => Log::Log4perl->get_logger("OESS.Link"),
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

=head2 load

    my $err = $link->load($db);

=cut
sub load {
    my $self = shift;
    my $db = shift;

    my $result = $db->get_link(link_id => $self->id);

    $self->{status} = $result->{status};
    $self->{ip_a} = $result->{ip_a};
    $self->{ip_z} = $result->{ip_z};
    $self->{interface_a_id} = $result->{interface_a_id};
    $self->{interface_z_id} = $result->{interface_z_id};
    $self->{metric} = $result->{metric};
    $self->{remote_urn} = $result->{remote_urn};
    $self->{name} = $result->{name};
    $self->{state} = $result->{link_state};

    return undef;
}

1;
