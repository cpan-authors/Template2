#!/usr/bin/perl -w
#
# t/unit-stash.t
#
# Unit tests for Template::Stash — constructor, get/set, dotop, getref,
# update, undefined, _assign, _reconstruct_ident, PRIVATE pattern.
#

use strict;
use lib qw( ./lib ../lib );
use Test::More;

use Template::Stash;
use Template::Exception;

#========================================================================
# Helper packages
#========================================================================

package Greet;
sub new    { bless { greeting => 'hello' }, shift }
sub greet  { return $_[0]->{greeting} }
sub shout  { return uc($_[0]->{greeting}) . '!' }
sub echo   { shift; return join(' ', @_) }
sub chain  { return $_[0] }

package HashyObj;
use base 'Template::Stash';
sub new {
    my ($class, $params) = @_;
    return $class->SUPER::new($params || {});
}

package BlessedHash;
sub new  { bless { color => 'red', size => 10 }, shift }
sub size { return 'method:' . $_[0]->{size} }

package BlessedArray;
sub new  { bless [10, 20, 30], shift }

package Kaboom;
sub new  { bless {}, shift }
sub boom { die "kaboom\n" }

package Overloaded;
use overload '""' => sub { 'stringified' }, fallback => 1;
sub new { bless {}, shift }

package main;

#========================================================================
#                         CONSTRUCTOR
#========================================================================

# empty constructor
{
    my $s = Template::Stash->new();
    isa_ok($s, 'Template::Stash', 'empty constructor');
    is($s->{'_PARENT'}, undef, 'fresh stash has undef _PARENT');
    ok(exists $s->{'global'}, 'fresh stash has global hash');
}

# constructor with hash ref
{
    my $s = Template::Stash->new({ x => 1, y => 2 });
    is($s->get('x'), 1, 'constructor hash ref: x');
    is($s->get('y'), 2, 'constructor hash ref: y');
}

# constructor with flat list
{
    my $s = Template::Stash->new(a => 10, b => 20);
    is($s->get('a'), 10, 'constructor flat list: a');
    is($s->get('b'), 20, 'constructor flat list: b');
}

# constructor params don't overwrite _PARENT
{
    my $s = Template::Stash->new({ _PARENT => 'sneaky' });
    is($s->{'_PARENT'}, undef, '_PARENT forced to undef by constructor');
}

#========================================================================
#                         GET — simple keys
#========================================================================

{
    my $s = Template::Stash->new({ name => 'Alice', age => 30, zero => 0 });

    is($s->get('name'), 'Alice', 'get simple string');
    is($s->get('age'),  30,      'get simple number');
    is($s->get('zero'), 0,       'get zero value');
    is($s->get('nope'), '',      'get undefined returns empty string');
}

#========================================================================
#                    GET — compound array ident
#========================================================================

{
    my $s = Template::Stash->new({
        user => { name => 'Bob', address => { city => 'NYC' } },
    });

    is($s->get(['user', 0, 'name', 0]), 'Bob',
        'get compound array: user.name');

    is($s->get(['user', 0, 'address', 0, 'city', 0]), 'NYC',
        'get compound array: user.address.city');
}

#========================================================================
#                    GET — dotted string parsing
#========================================================================

{
    my $s = Template::Stash->new({
        a => { b => { c => 'deep' } },
    });

    is($s->get('a.b.c'), 'deep', 'get dotted string: a.b.c');
    is($s->get('a.b'),   $s->get(['a', 0, 'b', 0]),
        'dotted string matches compound array form');
}

#========================================================================
#                    GET — code ref values
#========================================================================

{
    my $counter = 0;
    my $s = Template::Stash->new({
        greet   => sub { 'hi' },
        incr    => sub { ++$counter },
        add     => sub { $_[0] + $_[1] },
    });

    is($s->get('greet'), 'hi', 'get code ref: called automatically');
    is($s->get('incr'),  1,    'get code ref: side effect 1');
    is($s->get('incr'),  2,    'get code ref: side effect 2');
}

# code ref in nested hash
{
    my $s = Template::Stash->new({
        data => { gen => sub { 'generated' } },
    });
    is($s->get('data.gen'), 'generated', 'get nested code ref');
}

#========================================================================
#                    GET — private member access
#========================================================================

{
    my $s = Template::Stash->new({ _secret => 'hidden', visible => 'ok' });

    is($s->get('_secret'), '', 'get _ prefixed returns empty (private)');
    is($s->get('visible'), 'ok', 'get non-private works');
}

#========================================================================
#                    GET — hash/array data structures
#========================================================================

{
    my $s = Template::Stash->new({
        colors => ['red', 'green', 'blue'],
        config => { debug => 1, verbose => 0 },
    });

    my $colors = $s->get('colors');
    is(ref $colors, 'ARRAY', 'get array ref returns array ref');
    is($colors->[1], 'green', 'get array ref content intact');

    my $config = $s->get('config');
    is(ref $config, 'HASH', 'get hash ref returns hash ref');
    is($config->{debug}, 1, 'get hash ref content intact');
}

#========================================================================
#                    SET — simple assignment
#========================================================================

{
    my $s = Template::Stash->new({});

    $s->set('foo', 'bar');
    is($s->get('foo'), 'bar', 'set simple key');

    $s->set('foo', 'baz');
    is($s->get('foo'), 'baz', 'set overwrites existing');
}

#========================================================================
#                    SET — compound ident
#========================================================================

{
    my $s = Template::Stash->new({ user => {} });

    $s->set(['user', 0, 'name', 0], 'Carol');
    is($s->get(['user', 0, 'name', 0]), 'Carol',
        'set compound array ident');
}

#========================================================================
#                    SET — dotted string
#========================================================================

{
    my $s = Template::Stash->new({});

    $s->set('a.b', 'val');
    is($s->get('a.b'), 'val', 'set dotted string creates path');
}

#========================================================================
#                    SET — intermediate hash creation
#========================================================================

{
    my $s = Template::Stash->new({});

    $s->set('deep.nested.key', 'found');
    is($s->get('deep.nested.key'), 'found',
        'set creates intermediate hashes');

    my $deep = $s->get('deep');
    is(ref $deep, 'HASH', 'intermediate is a hash');
}

#========================================================================
#                    SET — default mode
#========================================================================

{
    my $s = Template::Stash->new({ existing => 'keep', falsy => 0, empty => '' });

    $s->set('existing', 'replace', 1);
    is($s->get('existing'), 'keep', 'default mode: skip if already true');

    $s->set('falsy', 'replaced', 1);
    is($s->get('falsy'), 'replaced', 'default mode: replace falsy value');

    $s->set('empty', 'filled', 1);
    is($s->get('empty'), 'filled', 'default mode: replace empty string');

    $s->set('brand_new', 'fresh', 1);
    is($s->get('brand_new'), 'fresh', 'default mode: set undefined var');
}

#========================================================================
#                    SET — private member rejection
#========================================================================

{
    my $s = Template::Stash->new({});

    my $result = $s->set('_private', 'value');
    is($result, '', 'set _ prefixed returns empty (rejected)');
    is($s->{'_private'}, undef, '_ prefixed not stored in stash hash');
}

#========================================================================
#                    SET — IMPORT via set('IMPORT', $hashref)
#========================================================================

{
    my $s = Template::Stash->new({});
    $s->set('foo', { alpha => 1, beta => 2 });
    is($s->get('foo.alpha'), 1, 'set hash ref: access sub-key');
}

#========================================================================
#                    DOTOP — hash root
#========================================================================

{
    my $s = Template::Stash->new({});
    my $root = { x => 10, y => 20 };

    is($s->dotop($root, 'x'), 10, 'dotop hash: simple key');
    is($s->dotop($root, 'y'), 20, 'dotop hash: another key');
    is($s->dotop($root, 'missing'), undef, 'dotop hash: missing key');
}

# dotop hash: code ref value
{
    my $s = Template::Stash->new({});
    my $root = { calc => sub { 42 } };

    is($s->dotop($root, 'calc'), 42, 'dotop hash: code ref called');
}

# dotop hash: code ref with args
{
    my $s = Template::Stash->new({});
    my $root = { add => sub { $_[0] + $_[1] } };

    is($s->dotop($root, 'add', [3, 7]), 10, 'dotop hash: code ref with args');
}

# dotop hash: lvalue creates intermediate hash
{
    my $s = Template::Stash->new({});
    my $root = {};

    my $result = $s->dotop($root, 'newkey', [], 1);
    is(ref $result, 'HASH', 'dotop hash lvalue: creates empty hash');
    ok(exists $root->{'newkey'}, 'dotop hash lvalue: key inserted in root');
}

# dotop hash: hash vmethod (keys, size, etc.)
{
    my $s = Template::Stash->new({});
    my $root = { a => 1, b => 2, c => 3 };

    my $keys = $s->dotop($root, 'keys');
    is(ref $keys, 'ARRAY', 'dotop hash vmethod: keys returns array');
    is(scalar @$keys, 3, 'dotop hash vmethod: correct key count');

    is($s->dotop($root, 'size'), 3, 'dotop hash vmethod: size');
}

# dotop hash: hash slice
{
    my $s = Template::Stash->new({});
    my $root = { a => 1, b => 2, c => 3 };

    my $slice = $s->dotop($root, ['a', 'c']);
    is(ref $slice, 'ARRAY', 'dotop hash slice: returns array ref');
    is_deeply($slice, [1, 3], 'dotop hash slice: correct values');
}

#========================================================================
#                    DOTOP — array root
#========================================================================

{
    my $s = Template::Stash->new({});
    my $root = [10, 20, 30, 40, 50];

    is($s->dotop($root, 0), 10, 'dotop array: index 0');
    is($s->dotop($root, 2), 30, 'dotop array: index 2');
    is($s->dotop($root, -1), 50, 'dotop array: negative index');
}

# dotop array: list vmethod
{
    my $s = Template::Stash->new({});
    my $root = [3, 1, 2];

    is($s->dotop($root, 'first'), 3,  'dotop array vmethod: first');
    is($s->dotop($root, 'last'),  2,  'dotop array vmethod: last');
    is($s->dotop($root, 'size'),  3,  'dotop array vmethod: size');

    my $sorted = $s->dotop($root, 'sort');
    is_deeply($sorted, [1, 2, 3], 'dotop array vmethod: sort');
}

# dotop array: code ref at index
{
    my $s = Template::Stash->new({});
    my $root = [sub { 'zero' }, 'one'];

    is($s->dotop($root, 0), 'zero', 'dotop array: code ref at index called');
    is($s->dotop($root, 1), 'one',  'dotop array: plain value at index');
}

# dotop array: array slice
{
    my $s = Template::Stash->new({});
    my $root = ['a', 'b', 'c', 'd'];

    my $slice = $s->dotop($root, [0, 2, 3]);
    is(ref $slice, 'ARRAY', 'dotop array slice: returns array ref');
    is_deeply($slice, ['a', 'c', 'd'], 'dotop array slice: correct values');
}

#========================================================================
#                    DOTOP — object root
#========================================================================

{
    my $s = Template::Stash->new({});
    my $obj = Greet->new();

    is($s->dotop($obj, 'greet'), 'hello', 'dotop object: method call');
    is($s->dotop($obj, 'shout'), 'HELLO!', 'dotop object: another method');
}

# dotop object: method with args
{
    my $s = Template::Stash->new({});
    my $obj = Greet->new();

    is($s->dotop($obj, 'echo', ['a', 'b']), 'a b',
        'dotop object: method with args');
}

# dotop object: method returns self (chaining)
{
    my $s = Template::Stash->new({});
    my $obj = Greet->new();

    my $result = $s->dotop($obj, 'chain');
    is($result, $obj, 'dotop object: method returning self');
}

# dotop object: hash-based fallback when method not found
{
    my $s = Template::Stash->new({});
    my $obj = BlessedHash->new();

    is($s->dotop($obj, 'color'), 'red',
        'dotop object: fallback to hash key');
    is($s->dotop($obj, 'size'), 'method:10',
        'dotop object: method takes priority over hash key');
}

# dotop object: real errors propagate (die with ref or existing method)
{
    my $s = Template::Stash->new({});
    my $obj = Kaboom->new();

    eval { $s->dotop($obj, 'boom') };
    like($@, qr/kaboom/, 'dotop object: method die propagates');
}

#========================================================================
#                    DOTOP — scalar root (vmethods)
#========================================================================

{
    my $s = Template::Stash->new({});
    my $text = 'Hello World';

    is($s->dotop($text, 'length'),  11,            'dotop scalar vmethod: length');
    is($s->dotop($text, 'lower'),   'hello world', 'dotop scalar vmethod: lower');
    is($s->dotop($text, 'upper'),   'HELLO WORLD', 'dotop scalar vmethod: upper');
    is($s->dotop($text, 'defined'), 1,             'dotop scalar vmethod: defined');
}

# dotop scalar: list promotion
{
    my $s = Template::Stash->new({});
    my $text = 'solo';

    is($s->dotop($text, 'first'), 'solo', 'dotop scalar: list promotion first');
    is($s->dotop($text, 'last'),  'solo', 'dotop scalar: list promotion last');
    is($s->dotop($text, 'size'),  1,      'dotop scalar: list promotion size (but text length wins)');
}

#========================================================================
#                    DOTOP — undef/private guards
#========================================================================

{
    my $s = Template::Stash->new({});

    is($s->dotop(undef, 'foo'),     undef, 'dotop undef root returns undef');
    is($s->dotop({x=>1}, undef),    undef, 'dotop undef item returns undef');
    is($s->dotop({x=>1}, '_priv'),  undef, 'dotop private item returns undef');
    is($s->dotop({x=>1}, '.priv'),  undef, 'dotop dot-prefixed returns undef');
}

#========================================================================
#                    DOTOP — stash-derived root (isa check)
#========================================================================

{
    my $sub = HashyObj->new({ flavor => 'vanilla' });
    my $s = Template::Stash->new({});

    is($s->dotop($sub, 'flavor'), 'vanilla',
        'dotop stash subclass: treats as hash root');
}

#========================================================================
#                    _ASSIGN — hash root
#========================================================================

{
    my $s = Template::Stash->new({});
    my $root = { x => 1 };

    $s->_assign($root, 'x', 0, 99);
    is($root->{x}, 99, '_assign hash: overwrites value');

    $s->_assign($root, 'new', 0, 'added');
    is($root->{'new'}, 'added', '_assign hash: adds new key');
}

# _assign hash: default mode
{
    my $s = Template::Stash->new({});
    my $root = { truthy => 'yes', falsy => 0, empty => '' };

    $s->_assign($root, 'truthy', 0, 'replaced', 1);
    is($root->{truthy}, 'yes', '_assign hash default: skip truthy');

    $s->_assign($root, 'falsy', 0, 'replaced', 1);
    is($root->{falsy}, 'replaced', '_assign hash default: replace falsy');
}

#========================================================================
#                    _ASSIGN — array root
#========================================================================

{
    my $s = Template::Stash->new({});
    my $root = [10, 20, 30];

    $s->_assign($root, '1', 0, 99);
    is($root->[1], 99, '_assign array: set by index');
}

# _assign array: default mode
{
    my $s = Template::Stash->new({});
    my $root = ['keep', 0, 'also_keep'];

    $s->_assign($root, '0', 0, 'replaced', 1);
    is($root->[0], 'keep', '_assign array default: skip truthy');

    $s->_assign($root, '1', 0, 'filled', 1);
    is($root->[1], 'filled', '_assign array default: replace falsy');
}

#========================================================================
#                    _ASSIGN — private rejection
#========================================================================

{
    my $s = Template::Stash->new({});
    my $root = {};

    my $result = $s->_assign($root, '_hidden', 0, 'val');
    is($result, undef, '_assign rejects _ prefix');
    ok(!exists $root->{'_hidden'}, '_assign: private key not stored');
}

#========================================================================
#                    _ASSIGN — object root
#========================================================================

{
    my $s = Template::Stash->new({});
    my $obj = Greet->new();

    my $result = $s->_assign($obj, 'echo', ['prefix'], 'suffix');
    is($result, 'prefix suffix', '_assign object: calls method with args + value');
}

#========================================================================
#                    GETREF — simple ident
#========================================================================

{
    my $s = Template::Stash->new({ count => 42 });

    my $ref = $s->getref('count');
    is(ref $ref, 'CODE', 'getref returns code ref');
    is($ref->(), 42, 'getref closure returns value');
}

# getref tracks current value
{
    my $s = Template::Stash->new({ val => 'original' });
    my $ref = $s->getref('val');

    $s->set('val', 'changed');
    is($ref->(), 'changed', 'getref closure tracks mutations');
}

#========================================================================
#                    GETREF — compound ident
#========================================================================

{
    my $s = Template::Stash->new({
        user => { name => 'Dan' },
    });

    my $ref = $s->getref(['user', 0, 'name', 0]);
    is(ref $ref, 'CODE', 'getref compound: returns code ref');
    is($ref->(), 'Dan', 'getref compound: correct value');
}

#========================================================================
#                    UPDATE — basic
#========================================================================

{
    my $s = Template::Stash->new({ a => 1 });
    $s->update({ a => 10, b => 20 });

    is($s->get('a'), 10, 'update: overwrites existing');
    is($s->get('b'), 20, 'update: adds new');
}

# update with import key
{
    my $s = Template::Stash->new({});
    $s->update({
        import => { x => 100, y => 200 },
        z      => 300,
    });

    is($s->get('x'), 100, 'update import: imported key x');
    is($s->get('y'), 200, 'update import: imported key y');
    is($s->get('z'), 300, 'update: regular key alongside import');
}

# update with non-hash import (ignored)
{
    my $s = Template::Stash->new({});
    $s->update({ import => 'not_a_hash', k => 'v' });
    is($s->get('k'), 'v', 'update: non-hash import ignored, other keys set');
}

#========================================================================
#                    UNDEFINED — non-strict
#========================================================================

{
    my $s = Template::Stash->new({});
    is($s->undefined('missing', []), '', 'undefined non-strict: empty string');
}

#========================================================================
#                    UNDEFINED — strict mode
#========================================================================

{
    my $s = Template::Stash->new({ _STRICT => 1 });

    eval { $s->undefined('missing_var', []) };
    ok($@, 'undefined strict: throws');
    isa_ok($@, 'Template::Exception', 'undefined strict: throws Exception');
    like("$@", qr/missing_var/, 'undefined strict: error names variable');
}

# strict mode with compound ident
{
    my $s = Template::Stash->new({ _STRICT => 1 });

    eval { $s->undefined(['foo', 0, 'bar', 0], []) };
    ok($@, 'undefined strict compound: throws');
    like("$@", qr/foo\.bar/, 'undefined strict compound: reconstructed ident');
}

#========================================================================
#                    UNDEFINED — .defined bypass (GH #170)
#========================================================================

{
    my $s = Template::Stash->new({ _STRICT => 1 });

    my $result;
    eval { $result = $s->undefined(['nope', 0, 'defined', 0], []) };
    is($@, '', '.defined bypass: no exception in strict mode');
    is($result, '', '.defined bypass: returns empty string');
}

#========================================================================
#                    _RECONSTRUCT_IDENT
#========================================================================

{
    my $s = Template::Stash->new({});

    is($s->_reconstruct_ident('foo'), 'foo',
        'reconstruct: simple string');

    is($s->_reconstruct_ident(['foo', 0, 'bar', 0]), 'foo.bar',
        'reconstruct: compound no args');

    is($s->_reconstruct_ident(['foo', 0, 'bar', ['x', 'y']]), "foo.bar('x', 'y')",
        'reconstruct: compound with args');

    is($s->_reconstruct_ident(['a', [10], 'b', 0]), 'a(10).b',
        'reconstruct: numeric arg not quoted');
}

#========================================================================
#                    PRIVATE pattern
#========================================================================

{
    my $s = Template::Stash->new({
        visible  => 'yes',
        _under   => 'no',
    });

    is($s->get('visible'), 'yes', 'PRIVATE: normal access works');
    is($s->get('_under'),  '',    'PRIVATE: _ prefix blocked');
}

# PRIVATE can be customized
{
    local $Template::Stash::PRIVATE = qr/^secret/;
    my $s = Template::Stash->new({ secret_x => 1, _ok => 2, public => 3 });

    is($s->get('secret_x'), '', 'custom PRIVATE: secret prefix blocked');
    is($s->get('_ok'), 2, 'custom PRIVATE: _ no longer blocked');
    is($s->get('public'), 3, 'custom PRIVATE: normal access works');
}

# PRIVATE can be disabled
{
    local $Template::Stash::PRIVATE = undef;
    my $s = Template::Stash->new({ _open => 'accessible' });
    is($s->get('_open'), 'accessible', 'PRIVATE disabled: _ prefix allowed');
}

#========================================================================
#                    GET — with object in stash
#========================================================================

{
    my $obj = Greet->new();
    my $s = Template::Stash->new({ greeter => $obj });

    is($s->get('greeter.greet'), 'hello', 'get object method via dotted string');
    is($s->get('greeter.shout'), 'HELLO!', 'get another object method');
    is($s->get(['greeter', 0, 'echo', ['hi', 'there']]), 'hi there',
        'get object method with args via compound ident');
}

#========================================================================
#                    GET — nested data + code refs
#========================================================================

{
    my $s = Template::Stash->new({
        data => {
            items => [1, 2, 3],
            gen   => sub { { nested => 'value' } },
        },
    });

    is($s->get('data.items.size'), 3, 'get nested array vmethod');
    is($s->get('data.gen.nested'), 'value', 'get through code ref returning hash');
}

#========================================================================
#                    SET — object method as setter
#========================================================================

{
    my $obj = Greet->new();
    my $s = Template::Stash->new({ obj => $obj });

    $s->set(['obj', 0, 'echo', 0], 'sent');
    # echo just returns its args, doesn't mutate — just verify no crash
    ok(1, 'set on object method does not crash');
}

#========================================================================
#                    SET — array index via compound ident
#========================================================================

{
    my $s = Template::Stash->new({ list => [10, 20, 30] });

    $s->set(['list', 0, '1', 0], 99);
    is($s->get(['list', 0, '1', 0]), 99, 'set array index via compound ident');
}

#========================================================================
#                    DOTOP — overloaded object
#========================================================================

{
    my $s = Template::Stash->new({});
    my $obj = Overloaded->new();

    # hash vmethods work on blessed hash with overloads
    my $keys = $s->dotop($obj, 'keys');
    is(ref $keys, 'ARRAY', 'dotop overloaded object: hash vmethod via fallback');
}

#========================================================================
#                    DOTOP — blessed array fallback
#========================================================================

{
    my $s = Template::Stash->new({});
    my $obj = BlessedArray->new();

    is($s->dotop($obj, 'size'), 3, 'dotop blessed array: list vmethod fallback');
    is($s->dotop($obj, 0), 10, 'dotop blessed array: index fallback');
}

#========================================================================
#                    DOTOP — _DEBUG mode
#========================================================================

{
    my $s = Template::Stash->new({ _DEBUG => 1 });

    eval { $s->dotop('plain_scalar', 'nonexistent_method') };
    like($@, qr/don't know how to access/, 'dotop debug: dies on unknown access');
}

#========================================================================
#                    DOTOP — multiple return values folded to list
#========================================================================

{
    my $s = Template::Stash->new({});
    my $root = { multi => sub { ('a', 'b', 'c') } };

    my $result = $s->dotop($root, 'multi');
    is(ref $result, 'ARRAY', 'dotop: multiple returns folded to array ref');
    is_deeply($result, ['a', 'b', 'c'], 'dotop: folded values correct');
}

#========================================================================
#                    DOTOP — single return not folded
#========================================================================

{
    my $s = Template::Stash->new({});
    my $root = { single => sub { 'only' } };

    my $result = $s->dotop($root, 'single');
    is($result, 'only', 'dotop: single return not wrapped in array');
}

#========================================================================
#                    CLONE/DECLONE — _PARENT chain
#========================================================================

{
    my $s = Template::Stash->new({ x => 1 });
    my $c1 = $s->clone({ x => 2 });
    my $c2 = $c1->clone({ x => 3 });

    is($c2->{'_PARENT'}, $c1, 'clone chain: c2 parent is c1');
    is($c1->{'_PARENT'}, $s,  'clone chain: c1 parent is root');
    is($s->{'_PARENT'}, undef, 'clone chain: root has no parent');

    is($c2->declone()->declone(), $s, 'double declone returns root');
}

#========================================================================
#                    GLOBAL namespace persistence
#========================================================================

{
    my $s = Template::Stash->new({});
    $s->set('global.shared', 'persists');

    my $clone = $s->clone();
    is($clone->get('global.shared'), 'persists',
        'global namespace visible in clones');
}

#========================================================================
#                    GET — 'import' vmethod on non-root hash
#========================================================================

{
    my $s = Template::Stash->new({
        myhash => { a => 1 },
    });

    my $hash = $s->get('myhash');
    is(ref $hash, 'HASH', 'non-root hash retrieved');

    # import should work as a vmethod on non-root hashes
    my $result = $s->dotop($hash, 'import', [{ b => 2 }]);
    is($hash->{b}, 2, 'import vmethod works on non-root hash');
}

# import blocked on root stash (only allowed explicitly)
{
    my $s = Template::Stash->new({ a => 1 });

    # On the root stash, import IS allowed (it's in the conditional)
    my $result = $s->dotop($s, 'import', [{ z => 99 }]);
    is($s->get('z'), 99, 'import vmethod allowed on root stash');
}

done_testing();
