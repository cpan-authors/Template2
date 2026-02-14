#============================================================= -*-perl-*-
#
# t/grammar-factory.t
#
# Test Template::Grammar factory registration and cleanup lifecycle.
# This test does NOT require Test::LeakTrace and runs for all users.
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

use Test::More tests => 9;

use Template;
use Template::Grammar;

# -----------------------------------------------------------------------
# Test 1-3: Grammar basic lifecycle
# -----------------------------------------------------------------------

{
    my $g = Template::Grammar->new();
    isa_ok( $g, 'Template::Grammar', 'new Grammar object' );

    my $factory = bless { id => 1 }, 'TestFactory';
    my $result = $g->install_factory($factory);
    is( $result, $factory, 'install_factory returns the factory' );

    undef $g;
    pass("Grammar DESTROY completes without error");
}

# -----------------------------------------------------------------------
# Test 4-5: Multiple Grammar instances share the factory
# -----------------------------------------------------------------------

{
    my $g1 = Template::Grammar->new();
    my $g2 = Template::Grammar->new();

    my $factory = bless { id => 2 }, 'TestFactory';
    $g1->install_factory($factory);
    $g2->install_factory($factory);

    undef $g1;
    pass("first Grammar can be destroyed while second holds factory");

    undef $g2;
    pass("second Grammar destruction completes cleanly");
}

# -----------------------------------------------------------------------
# Test 6-7: Template processing works correctly after factory cleanup
# -----------------------------------------------------------------------

my $tmpl = <<'EOT';
[% name %] is [% age %]
EOT

{
    my $out = '';
    my $tt = Template->new();
    $tt->process( \$tmpl, { name => 'Alice', age => 30 }, \$out );
    is( $out, "Alice is 30\n", "basic template processing works" );
}

# After tt is destroyed, create a new one — factory should be re-established
{
    my $out = '';
    my $tt = Template->new();
    $tt->process( \$tmpl, { name => 'Bob', age => 25 }, \$out );
    is( $out, "Bob is 25\n", "template processing works after previous Template destroyed" );
}

# -----------------------------------------------------------------------
# Test 8-9: FOREACH reproducer from issue #147
# -----------------------------------------------------------------------

my $foreach_tmpl = <<'EOT';
[% FOREACH item IN data -%]
[% item.val %]
[% FOREACH data IN item.stuff -%]
... one item
[% END -%]
[% END -%]
EOT

{
    my $out = '';
    my $tt = Template->new();
    my $vars = {
        data => [
            { val => 'hello' }
        ]
    };
    $tt->process( \$foreach_tmpl, $vars, \$out );
    is( $out, "hello\n", "FOREACH template without nested data" );
}

{
    my $out = '';
    my $tt = Template->new();
    my $vars = {
        data => [
            {
                val   => 'world',
                stuff => [ { name => 'bob' } ]
            }
        ]
    };
    $tt->process( \$foreach_tmpl, $vars, \$out );
    is( $out, "world\n... one item\n", "FOREACH template with nested data" );
}
