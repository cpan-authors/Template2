#============================================================= -*-perl-*-
#
# t/interp_newline.t
#
# Test that interpolate_text() preserves newlines in ${variable}
# references and tracks line numbers correctly.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Test::More;
use Template::Parser;

my $parser = Template::Parser->new({});

# Single-line variable: $dir should be '${ foo }'
{
    my $tokens = $parser->interpolate_text('before ${ foo } after', 1);
    my @directives = grep { ref $_ } @$tokens;
    is(scalar @directives, 1, 'one directive in single-line interp');
    is($directives[0][0], '${ foo }', 'directive text preserved');
}

# Multi-line variable: newlines in ${...} must NOT be replaced with spaces
{
    my $text = "before \${\nfoo\n} after";
    my $tokens = $parser->interpolate_text($text, 1);
    my @directives = grep { ref $_ } @$tokens;
    is(scalar @directives, 1, 'one directive in multi-line interp');
    like($directives[0][0], qr/\n/, 'newlines preserved in directive text');
    is($directives[0][0], "\${\nfoo\n}", 'exact directive text with newlines');
    is($directives[0][1], 3, 'line number advanced past newlines');
}

# Verify line counting is correct with multiple variables
{
    my $text = "line1\nline2 \${ a } line2\nline3 \${ b }";
    my $tokens = $parser->interpolate_text($text, 1);
    my @directives = grep { ref $_ } @$tokens;
    is(scalar @directives, 2, 'two directives found');
    is($directives[0][1], 2, 'first var on line 2');
    is($directives[1][1], 3, 'second var on line 3');
}

# End-to-end: INTERPOLATE mode renders multiline ${} correctly
{
    require Template;
    my $tt = Template->new({ INTERPOLATE => 1 });
    my $output = '';
    my $vars = { foo => 'HELLO' };
    $tt->process(\"start \${\nfoo\n} end", $vars, \$output) or die $tt->error;
    is($output, 'start HELLO end', 'multiline ${} interpolation works');
}

done_testing();
