#============================================================= -*-perl-*-
#
# t/compile_line.t
#
# Test that compiled templates have correct #line directives for block
# constructs (IF, FOREACH, WHILE, TRY, etc).
# Regression test for GH #306.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib ./blib/lib ../blib/lib ./blib/arch ../blib/arch );
use Template::Parser;
use Template::Directive;
use Test::More;

my $parser = Template::Parser->new({ FILE_INFO => 1 });

# Helper: parse template text and extract #line directives from compiled code
sub get_line_directives {
    my ($text) = @_;
    my $result = $parser->parse($text);
    return unless $result;
    my $code = $result->{BLOCK};
    my @lines;
    while ($code =~ /^#line\s+(\d+)\s+"([^"]+)"/mg) {
        push @lines, { line => $1, file => $2 };
    }
    return ($code, @lines);
}

# Test 1: Simple assignment - line should be 1
{
    my ($code, @lines) = get_line_directives('[% x = 3 %]');
    ok(@lines >= 1, 'simple assignment has #line directive');
    is($lines[0]{line}, 1, 'simple assignment at line 1');
}

# Test 2: IF block spanning multiple lines (the original GH #306 bug)
{
    my $tmpl = <<'EOF';
[% x = 3 %]
[% y = 3 %]
[% IF x == y %]
    blah blah
[% END %]
EOF
    my ($code, @lines) = get_line_directives($tmpl);
    ok(@lines >= 3, 'IF block template has at least 3 #line directives');
    is($lines[0]{line}, 1, 'first assignment at line 1');
    is($lines[1]{line}, 2, 'second assignment at line 2');
    is($lines[2]{line}, 3, 'IF block at line 3 (not line 5)');
}

# Test 3: FOREACH block
{
    my $tmpl = <<'EOF';
[% x = 1 %]
[% FOREACH item IN [1,2,3] %]
    [% item %]
[% END %]
EOF
    my ($code, @lines) = get_line_directives($tmpl);
    ok(@lines >= 2, 'FOREACH template has at least 2 #line directives');
    is($lines[0]{line}, 1, 'assignment before FOREACH at line 1');
    is($lines[1]{line}, 2, 'FOREACH block at line 2 (not line 4)');
}

# Test 4: WHILE block
{
    my $tmpl = <<'EOF';
[% x = 5 %]
[% WHILE x > 0 %]
    [% x = x - 1 %]
[% END %]
EOF
    my ($code, @lines) = get_line_directives($tmpl);
    ok(@lines >= 2, 'WHILE template has at least 2 #line directives');
    is($lines[0]{line}, 1, 'assignment before WHILE at line 1');
    is($lines[1]{line}, 2, 'WHILE block at line 2 (not line 4)');
}

# Test 5: TRY/CATCH block
{
    my $tmpl = <<'EOF';
[% x = 1 %]
[% TRY %]
    [% x %]
[% CATCH %]
    oops
[% END %]
EOF
    my ($code, @lines) = get_line_directives($tmpl);
    ok(@lines >= 2, 'TRY template has at least 2 #line directives');
    is($lines[0]{line}, 1, 'assignment before TRY at line 1');
    is($lines[1]{line}, 2, 'TRY block at line 2 (not line 6)');
}

# Test 6: Nested IF blocks
{
    my $tmpl = <<'EOF';
[% IF a %]
    [% IF b %]
        inner
    [% END %]
[% END %]
EOF
    my ($code, @lines) = get_line_directives($tmpl);
    ok(@lines >= 2, 'nested IF has at least 2 #line directives');
    is($lines[0]{line}, 1, 'outer IF at line 1');
    is($lines[1]{line}, 2, 'inner IF at line 2');
}

# Test 7: Single-line TRY (all in one tag) - GH #306 edge case
{
    my $tmpl = '[% TRY; x; CATCH; error; END %]';
    my ($code, @lines) = get_line_directives($tmpl);
    ok(@lines >= 1, 'single-line TRY has #line directive');
    is($lines[0]{line}, 1, 'single-line TRY at line 1');
}

# Test 8: SWITCH/CASE block
{
    my $tmpl = <<'EOF';
[% x = 'a' %]
[% SWITCH x %]
[% CASE 'a' %]
    alpha
[% CASE %]
    other
[% END %]
EOF
    my ($code, @lines) = get_line_directives($tmpl);
    ok(@lines >= 2, 'SWITCH template has at least 2 #line directives');
    is($lines[0]{line}, 1, 'assignment before SWITCH at line 1');
    is($lines[1]{line}, 2, 'SWITCH block at line 2 (not line 7)');
}

# Test 9: UNLESS block
{
    my $tmpl = <<'EOF';
[% x = 0 %]
[% UNLESS x %]
    shown
[% END %]
EOF
    my ($code, @lines) = get_line_directives($tmpl);
    ok(@lines >= 2, 'UNLESS template has at least 2 #line directives');
    is($lines[0]{line}, 1, 'assignment before UNLESS at line 1');
    is($lines[1]{line}, 2, 'UNLESS block at line 2 (not line 4)');
}

# Test 10: WRAPPER block
{
    my $tmpl = <<'EOF';
[% x = 1 %]
[% WRAPPER myblock %]
    content
[% END %]
EOF
    my ($code, @lines) = get_line_directives($tmpl);
    ok(@lines >= 2, 'WRAPPER template has at least 2 #line directives');
    is($lines[0]{line}, 1, 'assignment before WRAPPER at line 1');
    is($lines[1]{line}, 2, 'WRAPPER block at line 2 (not line 4)');
}

# Test 11: FILTER block
{
    my $tmpl = <<'EOF';
[% x = 1 %]
[% FILTER html %]
    <b>bold</b>
[% END %]
EOF
    my ($code, @lines) = get_line_directives($tmpl);
    ok(@lines >= 2, 'FILTER template has at least 2 #line directives');
    is($lines[0]{line}, 1, 'assignment before FILTER at line 1');
    is($lines[1]{line}, 2, 'FILTER block at line 2 (not line 4)');
}

done_testing();
