#============================================================= -*-perl-*-
#
# t/eval_perl_bypass.t
#
# Test that arbitrary Perl code cannot be executed via template.new()
# when EVAL_PERL is disabled. Regression test for GH #245.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Test::More tests => 11;
use Template;
use Template::Document;

my $marker = "/tmp/tt-eval-bypass-test-$$";

#------------------------------------------------------------------------
# 1. Unit test: Document->new as class method with string BLOCK works
#------------------------------------------------------------------------
{
    my $doc = Template::Document->new({
        BLOCK => 'sub { return "compiled" }',
    });
    ok( $doc, 'class method with string BLOCK succeeds' );
    is( $doc->process(bless {}, 'Template::DummyCtx'), 'compiled',
        'compiled block returns expected output' );
}

#------------------------------------------------------------------------
# 2. Unit test: $doc->new with string BLOCK is blocked
#------------------------------------------------------------------------
{
    my $doc = Template::Document->new({
        BLOCK => sub { return "original" },
    });
    ok( $doc, 'create a Document instance for testing' );

    my $bad = $doc->new({
        BLOCK => qq{open(my \$f, ">", "$marker"); close \$f; sub { "pwned" }},
    });
    ok( !$bad, 'instance method with string BLOCK returns undef' );
    ok( !-e $marker, 'no side effects from blocked eval' );
    like( $doc->error(), qr/instance method/,
        'error message mentions instance method' );
}

#------------------------------------------------------------------------
# 3. Unit test: $doc->new with string DEFBLOCKS is also blocked
#------------------------------------------------------------------------
{
    my $doc = Template::Document->new({
        BLOCK => sub { return "main" },
    });

    my $bad = $doc->new({
        BLOCK     => sub { return "ok" },
        DEFBLOCKS => {
            evil => qq{open(my \$f, ">", "$marker"); close \$f; sub { "pwned" }},
        },
    });
    ok( !$bad, 'instance method with string DEFBLOCKS returns undef' );
    ok( !-e $marker, 'no side effects from blocked DEFBLOCKS eval' );
}

#------------------------------------------------------------------------
# 4. End-to-end: exploit via template.new() is blocked
#------------------------------------------------------------------------
{
    my $tt = Template->new({ EVAL_PERL => 0 });
    my $output = "";
    my $vars = {
        exploit_args => {
            BLOCK => qq{open(my \$f, ">", "$marker"); close \$f; sub { "pwned" }},
        },
    };
    $tt->process(\q{before[% template.new(exploit_args) %]after}, $vars, \$output);
    ok( !-e $marker, 'template.new() exploit blocked end-to-end' );
    unlike( $output, qr/pwned/, 'no exploit output in result' );
}

#------------------------------------------------------------------------
# 5. End-to-end: exploit via component.new() is also blocked
#------------------------------------------------------------------------
{
    my $tt = Template->new({ EVAL_PERL => 0 });
    my $output = "";
    my $vars = {
        exploit_args => {
            BLOCK => qq{open(my \$f, ">", "$marker"); close \$f; sub { "pwned" }},
        },
    };
    $tt->process(\q{[% component.new(exploit_args) %]}, $vars, \$output);
    ok( !-e $marker, 'component.new() exploit blocked end-to-end' );
}

#------------------------------------------------------------------------
# Cleanup
#------------------------------------------------------------------------
END { unlink $marker if -e $marker }

#------------------------------------------------------------------------
# Dummy context for Document->process
#------------------------------------------------------------------------
package Template::DummyCtx;
sub visit { }
sub leave { }
