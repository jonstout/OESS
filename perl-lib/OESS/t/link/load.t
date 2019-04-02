#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
my $path;
BEGIN {
    if($FindBin::Bin =~ /(.*)/){
        $path = $1;
        $path = "$path/..";
    }
}
use lib "$path";


use Data::Dumper;
use Test::More tests => 2;

use OESS::Database;
use OESS::Link;


use OESSDatabaseTester;


my $db = OESS::Database->new(config => "$path/conf/database.xml");

my $link = OESS::Link->new(id => 21);
$link->load($db);

ok($link->name eq 'Link 21', 'Expected link name found');

$link->name('bah');
ok($link->name eq 'bah', 'Modified link name found');
