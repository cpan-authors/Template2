#!/usr/bin/perl -w
#
# t/stash_clone.t
#
# Unit tests for Template::Stash clone/declone, define_vmethod, undefined
#

use strict;
use lib qw( ./lib ../lib );
use Test::More tests => 32;

use Template;
use Template::Stash;
use Template::Config;

#------------------------------------------------------------------------
# clone — basic behavior
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({
        name => 'Alice',
        age  => 30,
    });

    my $clone = $stash->clone({ name => 'Bob' });
    ok(defined $clone, 'clone() returns a defined value');
    isa_ok($clone, 'Template::Stash', 'clone is a Stash object');

    is($clone->get('name'), 'Bob', 'cloned stash has overridden value');
    is($clone->get('age'), 30, 'cloned stash inherits parent value');

    # parent stash unchanged
    is($stash->get('name'), 'Alice', 'parent stash unchanged after clone');
}

#------------------------------------------------------------------------
# clone — with empty params
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({ x => 42 });
    my $clone = $stash->clone();
    is($clone->get('x'), 42, 'clone with no params inherits all values');
}

#------------------------------------------------------------------------
# clone — import parameter
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({ a => 1 });
    my $import_hash = { b => 2, c => 3 };
    my $clone = $stash->clone({ import => $import_hash });

    is($clone->get('a'), 1, 'clone with import inherits parent values');
    is($clone->get('b'), 2, 'clone imported value b');
    is($clone->get('c'), 3, 'clone imported value c');
}

#------------------------------------------------------------------------
# clone — import non-hash is ignored
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({ a => 1 });
    my $clone = $stash->clone({ import => 'not_a_hash' });
    is($clone->get('a'), 1, 'clone with non-hash import still works');
}

#------------------------------------------------------------------------
# declone — returns parent
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({ name => 'root' });
    my $clone = $stash->clone({ name => 'child' });

    my $parent = $clone->declone();
    is($parent, $stash, 'declone returns the parent stash');
    is($parent->get('name'), 'root', 'parent stash has original value');
}

#------------------------------------------------------------------------
# declone — on root stash returns self
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({ name => 'root' });
    my $result = $stash->declone();
    is($result, $stash, 'declone on root stash returns self');
}

#------------------------------------------------------------------------
# nested clone/declone
#------------------------------------------------------------------------

{
    my $root  = Template::Stash->new({ level => 'root' });
    my $child = $root->clone({ level => 'child' });
    my $grandchild = $child->clone({ level => 'grandchild' });

    is($grandchild->get('level'), 'grandchild', 'grandchild has its own value');

    my $back_to_child = $grandchild->declone();
    is($back_to_child->get('level'), 'child', 'declone returns to child');

    my $back_to_root = $back_to_child->declone();
    is($back_to_root->get('level'), 'root', 'double declone returns to root');
}

#------------------------------------------------------------------------
# modifications in clone don't affect parent
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({ color => 'red' });
    my $clone = $stash->clone();

    $clone->set('color', 'blue');
    is($clone->get('color'), 'blue', 'clone has modified value');
    is($stash->get('color'), 'red', 'parent unaffected by clone modification');
}

#------------------------------------------------------------------------
# define_vmethod — scalar
#------------------------------------------------------------------------

{
    Template::Stash->define_vmethod('scalar', 'test_double', sub {
        return $_[0] . $_[0];
    });

    my $stash = Template::Stash->new({});
    # verify it's accessible via template processing
    my $tt = Template->new();
    my $output = '';
    $tt->process(\q{[% x = 'ab'; x.test_double %]}, {}, \$output);
    is($output, 'abab', 'custom scalar vmethod works');
}

#------------------------------------------------------------------------
# define_vmethod — hash
#------------------------------------------------------------------------

{
    Template::Stash->define_vmethod('hash', 'test_key_count', sub {
        return scalar keys %{$_[0]};
    });

    my $tt = Template->new();
    my $output = '';
    $tt->process(\q{[% h.test_key_count %]}, { h => { a => 1, b => 2 } }, \$output);
    is($output, '2', 'custom hash vmethod works');
}

#------------------------------------------------------------------------
# define_vmethod — list
#------------------------------------------------------------------------

{
    Template::Stash->define_vmethod('list', 'test_sum', sub {
        my $sum = 0;
        $sum += $_ for @{$_[0]};
        return $sum;
    });

    my $tt = Template->new();
    my $output = '';
    $tt->process(\q{[% nums.test_sum %]}, { nums => [1, 2, 3, 4] }, \$output);
    is($output, '10', 'custom list vmethod works');
}

#------------------------------------------------------------------------
# define_vmethod — 'item' alias for 'scalar'
#------------------------------------------------------------------------

{
    Template::Stash->define_vmethod('item', 'test_item_vmethod', sub {
        return "item: $_[0]";
    });

    my $tt = Template->new();
    my $output = '';
    $tt->process(\q{[% x = 'foo'; x.test_item_vmethod %]}, {}, \$output);
    is($output, 'item: foo', 'item type alias for scalar works');
}

#------------------------------------------------------------------------
# define_vmethod — 'array' alias for 'list'
#------------------------------------------------------------------------

{
    Template::Stash->define_vmethod('array', 'test_array_len', sub {
        return scalar @{$_[0]};
    });

    my $tt = Template->new();
    my $output = '';
    $tt->process(\q{[% items.test_array_len %]}, { items => [qw(a b c)] }, \$output);
    is($output, '3', 'array type alias for list works');
}

#------------------------------------------------------------------------
# define_vmethod — invalid type dies
#------------------------------------------------------------------------

{
    eval { Template::Stash->define_vmethod('invalid_type', 'foo', sub { }) };
    like($@, qr/invalid vmethod type/i, 'define_vmethod dies on invalid type');
}

#------------------------------------------------------------------------
# undefined — non-strict mode returns empty string
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({});
    my $result = $stash->undefined('nonexistent', []);
    is($result, '', 'undefined returns empty string in non-strict mode');
}

#------------------------------------------------------------------------
# undefined — strict mode throws
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({ _STRICT => 1 });
    eval { $stash->undefined('missing_var', []) };
    ok($@, 'undefined throws in strict mode');
    like("$@", qr/undefined variable/i, 'error mentions undefined variable');
}

#------------------------------------------------------------------------
# get with STRICT mode
#------------------------------------------------------------------------

{
    my $tt = Template->new({ STRICT => 1 });
    my $output = '';
    my $ok = $tt->process(\q{[% TRY %][% no_such_var %][% CATCH %]caught: [% error.info %][% END %]}, {}, \$output);
    ok($ok, 'STRICT mode template processes with TRY/CATCH');
    like($output, qr/undefined variable.*no_such_var/i, 'STRICT mode catches undefined variable access');
}

#------------------------------------------------------------------------
# set and get with compound variable
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({});
    $stash->set('user.name', 'Alice');
    is($stash->get('user.name'), 'Alice', 'compound variable set/get works');
}

#------------------------------------------------------------------------
# update method
#------------------------------------------------------------------------

{
    my $stash = Template::Stash->new({ a => 1 });
    $stash->update({ a => 10, b => 20 });
    is($stash->get('a'), 10, 'update overwrites existing value');
    is($stash->get('b'), 20, 'update adds new value');
}
