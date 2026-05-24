#============================================================= -*-perl-*-
#
# t/zz-process-leak.t
#
# Check for memory leak when using Template process
#
# Written by Nicolas R. <atoomic@cpan.org>
#
# Copyright (C) 2018 cPanel Inc.  All Rights Reserved.
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
#========================================================================

use strict;
use warnings;
use lib qw( t/lib ./lib ../lib ../blib/arch );

use Template;
use Template::Plugin::Simple;

use Test::More;

plan( skip_all => "Developer test" ) unless ( $ENV{AUTOMATED_TESTING} or $ENV{RELEASE_TESTING} );

eval { require Test::LeakTrace };
if ($@) {
    plan( skip_all => 'Test::LeakTrace not installed' );
}

plan( tests => 6 );

note "Searching for leak using Test::LeakTrace...";

my $vars1 = {
    data => [
        {
            val => 'value1',
        }
    ]
};

my $vars2 = {
    data => [
        {
            val   => 'value2',
            stuff => [ { name => 'bob' } ]
        }
    ]
};

my @TESTS;

# we are adding it twice to show that this is not really a leak
#   as only the first one will leak
#   the memory 'leak' comes from the factory singleton in Template::Grammar
push @TESTS, {
    vars   => $vars1,
    expect => qq[value1\n],
} for 1 .. 2;

push @TESTS, {
    vars   => $vars2,
    expect => qq[value2\n... one item\n],
};

my ( $VARS, $OUT );
my $c = 0;
foreach my $t (@TESTS) {

    $VARS = $t->{vars};
    ++$c;

    my $no_leaks = Test::LeakTrace::no_leaks_ok( \&check_leak, "no leak when using for var$c" );
    is $OUT, $t->{expect}, "output matches what we expect for var$c" or diag $OUT;

    if ( !$no_leaks ) {
        diag "Memory leak detected when using var$c...";
        if ( eval { require Devel::Cycle; 1 } ) {
            Devel::Cycle::find_cycle( check_leak() );
        }
        else {
            diag "consider installing Devel::Cycle to detect leak";
        }
    }

}

exit;

sub check_leak {

    my $text = <<'EOT';
[% FOREACH item IN data -%]
[% item.val %]
[% FOREACH data IN item.stuff -%]
... one item
[% END -%]
[% END -%]
EOT

    $OUT = '';    # reset it before calling
    local $@;     # avoid a leak from $@
    my $tt = Template->new();
    eval { $tt->process( \$text, $VARS, \$OUT ); };

    return $tt;
}
