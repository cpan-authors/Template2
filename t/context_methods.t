#!/usr/bin/perl -w
#
# t/context_methods.t
#
# Unit tests for Template::Context methods that lack direct coverage:
#   define_filter, define_vmethod, define_block, define_view,
#   localise/delocalise, visit/leave, reset, plugin, filter, debugging
#

use strict;
use lib qw( ./lib ../lib );
use Test::More tests => 45;
use Scalar::Util 'blessed';

use Template;
use Template::Context;
use Template::Config;
use Template::Stash;
use Template::Constants qw( :debug );

my $dir = -d 't' ? 't/test' : 'test';

#------------------------------------------------------------------------
# localise / delocalise
#------------------------------------------------------------------------

{
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $context = $tt->service->context();
    my $stash   = $context->stash();

    $stash->set('animal', 'cat');
    is($stash->get('animal'), 'cat', 'variable set before localise');

    # localise creates a cloned stash
    $context->localise({ animal => 'dog' });
    my $cloned = $context->stash();
    isnt($cloned, $stash, 'localise creates a new stash');
    is($cloned->get('animal'), 'dog', 'localised variable has new value');

    # delocalise reverts to parent stash
    $context->delocalise();
    is($context->stash->get('animal'), 'cat', 'delocalise restores parent stash');
}

#------------------------------------------------------------------------
# visit / leave
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    my $blocks_a = { alpha => sub { 'block alpha' } };
    my $blocks_b = { beta  => sub { 'block beta'  } };

    $context->visit(undef, $blocks_a);
    is(scalar @{ $context->{ BLKSTACK } }, 1, 'visit pushes to BLKSTACK');

    $context->visit(undef, $blocks_b);
    is(scalar @{ $context->{ BLKSTACK } }, 2, 'second visit pushes another entry');

    $context->leave();
    is(scalar @{ $context->{ BLKSTACK } }, 1, 'leave pops from BLKSTACK');

    $context->leave();
    is(scalar @{ $context->{ BLKSTACK } }, 0, 'BLKSTACK empty after all leaves');
}

#------------------------------------------------------------------------
# reset
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    # add a block via visit
    $context->visit(undef, { test_block => sub { 'hello' } });
    ok(scalar @{ $context->{ BLKSTACK } } > 0, 'BLKSTACK has entries before reset');

    $context->reset();
    is(scalar @{ $context->{ BLKSTACK } }, 0, 'reset clears BLKSTACK');
    is(ref $context->{ BLOCKS }, 'HASH', 'BLOCKS is still a hash after reset');
}

#------------------------------------------------------------------------
# define_block
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    # define a block with a code reference
    my $code = sub { return "hello from block" };
    my $result = $context->define_block('my_block', $code);
    ok($result, 'define_block returns true for coderef');
    is($context->{ BLOCKS }->{ my_block }, $code, 'block stored in BLOCKS hash');

    # define a block with text (gets compiled)
    $result = $context->define_block('text_block', 'Hello [% name %]');
    ok($result, 'define_block returns true for text');
    ok(ref $context->{ BLOCKS }->{ text_block }, 'text block compiled to reference');
}

#------------------------------------------------------------------------
# define_filter
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    # define a static filter
    my $upper_filter = sub { return uc $_[0] };
    my $ok = $context->define_filter('my_upper', $upper_filter);
    is($ok, 1, 'define_filter returns 1 on success');

    # verify it can be retrieved via filter()
    my $filter = $context->filter('my_upper');
    ok(ref $filter eq 'CODE', 'filter() returns a coderef');
    is($filter->('hello'), 'HELLO', 'custom filter works correctly');

    # define a dynamic filter (factory)
    my $repeat_factory = sub {
        my ($context, @args) = @_;
        my $count = $args[0] || 2;
        return sub { return $_[0] x $count };
    };
    $ok = $context->define_filter('my_repeat', $repeat_factory, 1);
    is($ok, 1, 'define_filter returns 1 for dynamic filter');
}

#------------------------------------------------------------------------
# define_vmethod
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    # define a scalar vmethod via the context
    $context->define_vmethod('scalar', 'my_reverse', sub {
        return scalar reverse $_[0];
    });

    # verify it works through template processing
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $output = '';
    $tt->process(\qq{[% x = 'hello'; x.my_reverse %]}, {}, \$output);
    is($output, 'olleh', 'custom scalar vmethod works via template');
}

#------------------------------------------------------------------------
# filter() — caching behavior
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    # fetch a built-in filter
    my $html_filter = $context->filter('html');
    ok(ref $html_filter eq 'CODE', 'html filter is a coderef');
    is($html_filter->('<b>test</b>'), '&lt;b&gt;test&lt;/b&gt;', 'html filter escapes correctly');

    # fetch the same filter again (should come from cache)
    my $html_filter2 = $context->filter('html');
    is($html_filter, $html_filter2, 'filter() returns cached filter on second call');

    # fetch a filter with alias
    my $uc_filter = $context->filter('upper', undef, 'my_alias');
    ok(ref $uc_filter eq 'CODE', 'upper filter with alias is a coderef');

    # the alias should be cached
    my $aliased = $context->filter('my_alias');
    is($aliased, $uc_filter, 'filter cached under alias');
}

#------------------------------------------------------------------------
# filter() — error for non-existent filter
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    my $filter = $context->filter('completely_nonexistent_filter');
    ok(!defined $filter, 'filter() returns undef for unknown filter');
    like($context->error(), qr/not found/, 'error message mentions not found');
}

#------------------------------------------------------------------------
# plugin() — load a standard plugin
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    my $plugin = eval { $context->plugin('Table', [[ 1, 2, 3, 4 ], { rows => 2 }]) };
    ok(defined $plugin, 'plugin() loads Table plugin');
    ok(ref $plugin, 'plugin returns an object');
}

#------------------------------------------------------------------------
# plugin() — error for non-existent plugin
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    eval { $context->plugin('Completely_Nonexistent_Plugin_XYZ', []) };
    ok($@, 'plugin() throws for non-existent plugin');
    like("$@", qr/plugin not found|not found|plugin/i, 'error mentions plugin issue');
}

#------------------------------------------------------------------------
# debugging()
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        DEBUG        => DEBUG_DIRS,
    });

    ok($context->{ DEBUG_DIRS }, 'DEBUG_DIRS enabled initially');

    # turn off debugging
    $context->debugging('off');
    ok(!$context->{ DEBUG_DIRS }, 'debugging("off") disables DEBUG_DIRS');

    # turn on debugging
    $context->debugging('on');
    ok($context->{ DEBUG_DIRS }, 'debugging("on") enables DEBUG_DIRS');

    # numeric on/off
    $context->debugging('0');
    ok(!$context->{ DEBUG_DIRS }, 'debugging("0") disables DEBUG_DIRS');

    $context->debugging('1');
    ok($context->{ DEBUG_DIRS }, 'debugging("1") enables DEBUG_DIRS');

    # format
    $context->debugging('format', '<!-- $file:$line -->');
    is($context->{ DEBUG_FORMAT }, '<!-- $file:$line -->', 'debugging sets custom format');
}

#------------------------------------------------------------------------
# context process/include via template
#------------------------------------------------------------------------

{
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        TRIM         => 1,
    });

    # test process() through Template
    my $output = '';
    my $ok = $tt->process(\q{[% BLOCK greet %]Hi [% name %][% END %][% PROCESS greet name='World' %]}, {}, \$output);
    ok($ok, 'PROCESS directive works');
    is($output, 'Hi World', 'PROCESS output is correct');

    # test include() through Template — INCLUDE localises stash
    $output = '';
    $ok = $tt->process(\q{[% name = 'outer' %][% BLOCK inner %][% name = 'inner' %][% name %][% END %][% INCLUDE inner %] [% name %]}, {}, \$output);
    ok($ok, 'INCLUDE directive works');
    is($output, 'inner outer', 'INCLUDE localises variable scope');
}

#------------------------------------------------------------------------
# stash() accessor
#------------------------------------------------------------------------

{
    my $context = Template::Config->context({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    my $stash = $context->stash();
    ok(defined $stash, 'stash() returns a defined value');
    ok(blessed($stash), 'stash() returns a blessed object');
}

#------------------------------------------------------------------------
# define_view
#------------------------------------------------------------------------

{
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    my $output = '';
    my $ok = $tt->process(\q{[% VIEW my_view prefix='view/' %][% END %][% my_view.prefix %]}, {}, \$output);
    ok($ok, 'VIEW directive works');
    is($output, 'view/', 'VIEW prefix accessible');
}
