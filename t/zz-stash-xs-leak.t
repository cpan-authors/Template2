#============================================================= -*-perl-*-
#
# t/stash-xs-leak.t
#
# Template script to investigate a leak in the XS Stash
#
# Written by Andy Wardley <abw@wardley.org>
#
# Copyright (C) 1996-2009 Andy Wardley.  All Rights Reserved.
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib ../blib/lib ../blib/arch ./blib/lib ./blib/arch );
use Template::Constants qw( :status );
use Template;
use Template::Config;

use Test::More;

# belt and braces
unless (grep(/--dev/, @ARGV)) {
    plan( skip_all => 'Internal test for developer, add the --dev flag to run' );
}

unless ( $ENV{AUTOMATED_TESTING} or $ENV{RELEASE_TESTING} ) {
    plan( skip_all => "Developer tests not required for installation" );
}

# only run the test when compiled with Template::Stash
if ( $Template::Config::STASH ne 'Template::Stash::XS' ) {
    plan( skip_all => 'Template::Config is not using Template::Stash::XS' );
}

require Template::Stash::XS;

my $stash = Template::Stash::XS->new( { x => 10, y => { } } );

my ($a, $b) = (5, 10_000);

print <<EOF;
Use 'top' to monitor the memory consumption.  It should remain static.
(alas, Devel::Mallinfo doesn't seem to work on my Mac)
EOF

while ($a--) {
    my $c = $b;
    print "$a running...\n";
    while ($c--) {
        $stash->get( ['x', 0, 'y', 0] );
        $stash->get( ['x', 0, 'length', 0] );
        $stash->get( ['y', 0, 'length', 0] );
    }
    print "pausing...\n";
    sleep 1;
}
