#============================================================= -*-perl-*-
#
# t/compile_lines.t
#
# Verify that #line directives in compiled templates point to the
# opening keyword (IF, FOREACH, etc.), not to the closing END tag.
# Regression test for GH #306.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Test::More;
use Template::Parser;

my @tests = (
    {
        name     => 'IF block uses IF line, not END line',
        template => "[% x = 1 %]\n[% y = 1 %]\n[% IF x == y %]\n    ok\n[% END %]\n",
        expect   => [ 1, 2, 3 ],
    },
    {
        name     => 'nested IF and FOREACH',
        template => "[% IF x %]\n[% FOREACH y IN list %]\n[% y %]\n[% END %]\n[% END %]\n",
        expect   => [ 1, 2, 3 ],
    },
    {
        name     => 'IF with ELSIF and ELSE',
        template => "[% IF x %]\na\n[% ELSIF y %]\nb\n[% ELSE %]\nc\n[% END %]\n",
        expect   => [ 1 ],
    },
    {
        name     => 'SWITCH block',
        template => "[% SWITCH x %]\n[% CASE 1 %]one\n[% CASE 2 %]two\n[% END %]\n",
        expect   => [ 1 ],
    },
    {
        name     => 'WHILE block',
        template => "[% x = 3 %]\n[% WHILE x > 0; x = x - 1; END %]\n",
        expect   => [ 1, 2, 2 ],
    },
    {
        name     => 'postfix IF preserves correct line',
        template => "[% x = 1 %]\n[% y = 2 %]\n[% z = x IF x > 0 %]\n",
        expect   => [ 1, 2, 3 ],
    },
    {
        name     => 'WRAPPER block',
        template => "[% BLOCK wrap %]<[% content %]>[% END %]\n[% x = 1 %]\n[% WRAPPER wrap %]inner[% END %]\n",
        expect   => [ 2, 3 ],
    },
    {
        name     => 'TRY/CATCH block',
        template => "[% x = 1 %]\n[% TRY %]\nok\n[% CATCH %]\nerr\n[% END %]\n",
        expect   => [ 1, 2 ],
    },
);

plan tests => scalar @tests;

my $parser = Template::Parser->new({});

for my $test (@tests) {
    my $doc = $parser->parse($test->{template});
    my $code = $doc->{BLOCK};

    my @lines;
    while ($code =~ /^#line\s+(\d+)\s/mg) {
        push @lines, $1;
    }

    is_deeply(\@lines, $test->{expect}, $test->{name})
        or diag "Got #line directives: @lines\n  Expected: @{$test->{expect}}";
}
