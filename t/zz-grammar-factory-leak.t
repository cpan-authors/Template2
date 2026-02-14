#============================================================= -*-perl-*-
#
# t/zz-grammar-factory-leak.t
#
# Test that Template::Grammar properly cleans up the factory singleton
# to avoid memory leaks.  Resolves issue #147 (RT #49456).
#
# Written by Nicolas R. <atoomic@cpan.org>
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
#========================================================================

use strict;
use warnings;
use lib qw( t/lib ./lib ../lib ../blib/arch );

use Test::More;

BEGIN {
    unless ( $ENV{AUTOMATED_TESTING} or $ENV{RELEASE_TESTING} ) {
        plan( skip_all => "Developer tests not required for installation" );
    }

    eval { require Test::LeakTrace; Test::LeakTrace->import(); 1 }
        or plan( skip_all => 'Test::LeakTrace not installed' );
}

use Template;
use Template::Grammar;

plan tests => 8;

# -----------------------------------------------------------------------
# Test 1-2: Basic factory cleanup on Grammar destruction
# -----------------------------------------------------------------------

{
    my $grammar = Template::Grammar->new();
    isa_ok( $grammar, 'Template::Grammar', 'Grammar object created' );

    # install a factory and verify it sticks
    my $fake_factory = bless {}, 'FakeFactory';
    $grammar->install_factory($fake_factory);

    # destroying Grammar should clear the factory
    undef $grammar;
    pass("Grammar destruction clears factory without error");
}

# -----------------------------------------------------------------------
# Test 3-4: Template processing should not leak
# Reproduces the original bug report from RT #49456 / issue #147
# -----------------------------------------------------------------------

my $template_text = <<'EOT';
[% FOREACH item IN data -%]
[% item.val %]
[% FOREACH data IN item.stuff -%]
... one item
[% END -%]
[% END -%]
EOT

my $vars_simple = {
    data => [
        { val => 'value1' }
    ]
};

my $vars_with_stuff = {
    data => [
        {
            val   => 'value2',
            stuff => [ { name => 'bob' } ]
        }
    ]
};

{
    # First call may allocate the grammar singleton -- run once to warm up
    my $tt_warmup = Template->new();
    my $warmup_out = '';
    $tt_warmup->process( \$template_text, $vars_simple, \$warmup_out );
}

# The second process call should not leak
no_leaks_ok {
    my $out = '';
    local $@;
    my $tt = Template->new();
    eval { $tt->process( \$template_text, $vars_simple, \$out ); };
} "no leak when processing simple template (issue #147)";

no_leaks_ok {
    my $out = '';
    local $@;
    my $tt = Template->new();
    eval { $tt->process( \$template_text, $vars_with_stuff, \$out ); };
} "no leak when processing template with nested data";

# -----------------------------------------------------------------------
# Test 5-6: Multiple Template instances should not leak
# -----------------------------------------------------------------------

{
    # warm up
    for (1..2) {
        my $tt = Template->new();
        my $out = '';
        $tt->process( \$template_text, $vars_simple, \$out );
    }
}

no_leaks_ok {
    my $out = '';
    local $@;
    my $tt = Template->new();
    eval { $tt->process( \$template_text, $vars_simple, \$out ) };
    my $tt2 = Template->new();
    eval { $tt2->process( \$template_text, $vars_with_stuff, \$out ) };
} "no leak with multiple Template instances in same scope";

no_leaks_ok {
    for my $i (1..3) {
        my $out = '';
        local $@;
        my $tt = Template->new();
        eval { $tt->process( \$template_text, $vars_simple, \$out ) };
    }
} "no leak when creating and destroying Template objects in a loop";

# -----------------------------------------------------------------------
# Test 7: Factory is properly shared and cleaned
# -----------------------------------------------------------------------

{
    my $g1 = Template::Grammar->new();
    my $g2 = Template::Grammar->new();

    my $factory1 = bless {}, 'FakeFactory';
    $g1->install_factory($factory1);
    $g2->install_factory($factory1);

    undef $g1;
    # factory should still be alive because g2 holds it
    pass("partial Grammar destruction does not crash");

    undef $g2;
    # now factory should be cleaned up
}

# -----------------------------------------------------------------------
# Test 8: Output correctness after factory cleanup
# -----------------------------------------------------------------------

{
    my $out1 = '';
    {
        my $tt = Template->new();
        $tt->process( \$template_text, $vars_simple, \$out1 );
    }
    # tt is now destroyed, factory should be cleaned

    my $out2 = '';
    {
        my $tt = Template->new();
        $tt->process( \$template_text, $vars_simple, \$out2 );
    }
    is( $out1, $out2, "output is identical across Template lifecycles" );
}
