#!/usr/bin/perl

use strict;
use warnings;

use OESS::Workgroup;

package OESS::DB::User;

=head2 fetch
=cut
sub fetch{
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};

    my $user = $db->execute_query("select * from user where user_id = ?",[$user_id]);
    
    if(!defined($user) || !defined($user->[0])){
        return;
    }


    $user = $user->[0];
    $user->{'workgroups'} = ();
    my $workgroups = $db->execute_query("select workgroup_id from user_workgroup_membership where user_id = ?",[$user_id]);
    $user->{'is_admin'} = 0;
    foreach my $workgroup (@$workgroups){
        my $wg = OESS::Workgroup->new(db => $db, workgroup_id => $workgroup->{'workgroup_id'});
        push(@{$user->{'workgroups'}}, $wg);
        if($wg->type() eq 'admin'){
            $user->{'is_admin'} = 1;
        }
    }

    #if they are an admin they are a part of every workgroup
    if($user->{'is_admin'}){
        $user->{'workgroups'} = ();
        my $workgroups = $db->execute_query("select workgroup_id from workgroup",[]);
        
        foreach my $workgroup (@$workgroups){
            push(@{$user->{'workgroups'}}, OESS::Workgroup->new(db => $db, workgroup_id => $workgroup->{'workgroup_id'}));
        }

    }

    return $user;
}


=head2 get_workgroups

=cut
sub get_workgroups {
    my $args = { @_ };

    if (!defined $args->{db}) {
        return;
    }
    if (!defined $args->{user_id}) {
        return;
    }

    my $query = "
    SELECT workgroup.*
    FROM user
    JOIN user_workgroup_membership ON user.user_id=user_workgroup_membership.user_id
    JOIN workgroup ON user_workgroup_membership.workgroup_id=workgroup.workgroup_id
    WHERE user.user_id=?";

    my $workgroups = $args->{db}->execute_query($query, [$args->{user_id}]);
    if (!defined $workgroups || @$workgroups < 1) {
        return [];
    }

    return $workgroups;
}

=head2 get
=cut
sub get {
    my $args = { @_ };

    my $params = [];
    my $values = [];

    if (defined $args->{user_id}) {
        push @$params, "remote_auth.user_id=?";
        push @$values, $args->{user_id};
    }
    if (defined $args->{auth_name}) {
        push @$params, "remote_auth.auth_name=?";
        push @$values, $args->{auth_name};
    }
    my $where = (@$params > 0) ? 'where ' . join(' and ', @$params) : '';

    my $query = "
    SELECT remote_auth.user_id, remote_auth.auth_name as username, user.given_names as first_name, user.family_name as last_name,
           user.is_admin, user.type, user.email
    FROM remote_auth
    JOIN user ON user.user_id=remote_auth.user_id
    $where";

    my $users = $args->{db}->execute_query($query, $values);
    if (!defined $users || @$users < 1) {
        return;
    }

    return $users->[0];
}

=head2 find_user_by_remote_auth
=cut
sub find_user_by_remote_auth{
    my %params = @_;
    my $db = $params{'db'};
    my $remote_user = $params{'remote_user'};

    my $user_id = $db->execute_query("select remote_auth.user_id from remote_auth where remote_auth.auth_name = ?",[$remote_user]);
    if(!defined($user_id) || !defined($user_id->[0])){
        return;
    }

    return $user_id->[0];
}

1;
