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
use Test::More tests => 1;

use OESS::Database;
use OESS::Path;


use OESSDatabaseTester;


my $db = OESS::Database->new(config => "$path/conf/database.xml");

my $path2 = OESS::Path->new(id => 1971);
$path2->load($db);

ok(@{$path2->links} == 2, 'Expected link count loaded');
