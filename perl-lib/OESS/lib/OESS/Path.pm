package OESS::Path;

use strict;
use warnings;

use Data::Dumper;
use Graph;
use Log::Log4perl;

use OESS::DB;
use OESS::Link;

=head1 OESS::Path

    use OESS::Path;

    my $path = OESS::Path->new;

    $path->save($db); # Save $path->id to database
    $path->load($db); # Read $path->id from database

This package provides an object for quickly creating a Path from a
json model. Ideally this model would be passed directly from the web
api.

=cut

=head2 new

    my $path = OESS::Path->new(
      type => '',
      id   =>  7,
      circuit_id => 7,
      links => [
        OESS::Link,
        OESS::Link
      ]
    );

=cut
sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        log => Log::Log4perl->get_logger("OESS.Path"),
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

=head2 links

=cut
sub links {
    my $self = shift;
    my $links = shift;
    if (defined $links) { $self->{links} = $links; }
    return $self->{links};
}

=head2 hops

=cut
sub hops {
    my $self = shift;
    my $src = shift;
    my $dst = shift;

    my $g = Graph->new(undirected => 1);
    foreach my $l (@{$self->links}) {
        $g->add_edge($l->{node_a_loopback}, $l->{node_z_loopback});
    }
    my @path = $g->SP_Dijkstra($src, $dst);

    return \@path;
}

=head2 load

    my $err = $path->load($db);

=cut
sub load {
    my $self = shift;
    my $db = shift;

    my $links = $db->get_path_links_by_id(path_id => $self->id);
    $self->{links} = [];
    foreach my $link (@$links) {
        my $l = OESS::Link->new(
            id              => $link->{link_id},
            node_a          => $link->{node_a},
            node_a_loopback => $link->{node_a_loopback},
            name            => $link->{name},
            port_no_a       => $link->{port_no_a},
            ip_a            => $link->{ip_a},
            interface_a     => $link->{interface_a},
            interface_a_id  => $link->{interface_a_id},
            node_z          => $link->{node_z},
            node_z_loopback => $link->{node_z_loopback},
            port_no_z       => $link->{port_no_z},
            ip_z            => $link->{ip_z},
            interface_z     => $link->{interface_z},
            interface_z_id  => $link->{interface_z_id}
        );
        push @{$self->{links}}, $l;
    }

    return undef;
}

1;
