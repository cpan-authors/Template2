#============================================================= -*-perl-*-
#
# t/compile-line-numbers.t
#
# Test that compiled templates emit correct #line directives,
# particularly for compound directives (IF, FOREACH, WHILE, etc.)
# where the parser previously reported the END line instead of the
# opening keyword line.
#
# GH #306
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use File::Path qw( rmtree mkpath );
use File::Spec;
use Template;
use Test::More tests => 8;

my $tmpdir      = File::Spec->catdir(File::Spec->tmpdir(), "tt-line-test-$$");
my $src_dir     = File::Spec->catdir($tmpdir, 'src');
my $compile_dir = File::Spec->catdir($tmpdir, 'compiled');

mkpath($src_dir);
mkpath($compile_dir);

END { rmtree($tmpdir) if $tmpdir && -d $tmpdir }

# Helper: write a template file, compile it, and return the #line numbers
sub compiled_lines {
    my ($name, $template_text) = @_;

    # Write template file
    my $src_file = File::Spec->catfile($src_dir, $name);
    open my $wfh, '>', $src_file or die "Cannot write $src_file: $!";
    print $wfh $template_text;
    close $wfh;

    my $tt = Template->new({
        INCLUDE_PATH => $src_dir,
        COMPILE_DIR  => $compile_dir,
        COMPILE_EXT  => '.ttc',
    });
    my $output;
    $tt->process($name, {}, \$output) or die $tt->error;

    # Find the compiled file
    my @compiled;
    require File::Find;
    File::Find::find(
        { wanted => sub { push @compiled, $_ if /\.ttc$/ }, no_chdir => 1 },
        $compile_dir
    );
    die "No compiled file found" unless @compiled;
    open my $fh, '<', $compiled[-1] or die "Cannot read $compiled[-1]: $!";
    my @lines;
    while (<$fh>) {
        if (/^#line\s+(\d+)\s/) {
            push @lines, $1;
        }
    }
    close $fh;

    # Clean up compiled files for next test
    rmtree($compile_dir);
    mkpath($compile_dir);

    return @lines;
}

# Test 1: Basic IF (GH #306 original report)
{
    my @lines = compiled_lines('if_test.tt', <<'TMPL');
[% x = 3 %]
[% y = 3 %]
[% IF x == y %]
    blah
[% END %]
TMPL
    # x=3 on line 1, y=3 on line 2, IF on line 3
    is($lines[0], 1, 'IF template: SET x on line 1');
    is($lines[1], 2, 'IF template: SET y on line 2');
    is($lines[2], 3, 'IF template: IF on line 3 (not END line)');
}

# Test 2: FOREACH
{
    my @lines = compiled_lines('foreach_test.tt', <<'TMPL');
[% x = 1 %]
[% FOREACH item IN [1, 2, 3] %]
    [% item %]
[% END %]
TMPL
    is($lines[0], 1, 'FOREACH template: SET on line 1');
    is($lines[1], 2, 'FOREACH template: FOREACH on line 2 (not END line)');
}

# Test 3: WHILE
{
    my @lines = compiled_lines('while_test.tt', <<'TMPL');
[% x = 0 %]
[% WHILE x < 3; x = x + 1 %]
    [% x %]
[% END %]
TMPL
    is($lines[0], 1, 'WHILE template: SET on line 1');
    is($lines[1], 2, 'WHILE template: WHILE on line 2 (not END line)');
}

# Test 4: Nested IF
{
    my @lines = compiled_lines('nested_if_test.tt', <<'TMPL');
[% IF 1 %]
    [% IF 1 %]
        inner
    [% END %]
[% END %]
TMPL
    is($lines[0], 1, 'nested IF: outer IF on line 1');
}
