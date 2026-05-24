#!/usr/bin/perl -w
#
# t/iterator_methods.t
#
# Unit tests for Template::Iterator methods: constructor input coercion,
# get_first/get_next/get_all lifecycle, accessor methods, AUTOLOAD,
# and edge cases.
#

use strict;
use lib qw( ./lib ../lib );
use Test::More tests => 95;

use Template::Iterator;
use Template::Constants;

#------------------------------------------------------------------------
# constructor — array reference (standard case)
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'a', 'b', 'c' ]);
    ok(defined $iter, 'constructor accepts array ref');

    my $val = $iter->get_first();
    is($val, 'a', 'array ref: first item correct');
    is($iter->size(), 3, 'array ref: size correct');
}

#------------------------------------------------------------------------
# constructor — hash reference (sorted key/value pairs)
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new({
        cherry => 'red',
        apple  => 'green',
        banana => 'yellow',
    });
    ok(defined $iter, 'constructor accepts hash ref');

    my $first = $iter->get_first();
    is(ref $first, 'HASH', 'hash input: items are hash refs');
    is($first->{key}, 'apple', 'hash input: sorted by key (apple first)');
    is($first->{value}, 'green', 'hash input: value correct for apple');

    my $second = $iter->get_next();
    is($second->{key}, 'banana', 'hash input: banana second');
    is($second->{value}, 'yellow', 'hash input: value correct for banana');

    my $third = $iter->get_next();
    is($third->{key}, 'cherry', 'hash input: cherry third');
    is($third->{value}, 'red', 'hash input: value correct for cherry');

    is($iter->size(), 3, 'hash input: size matches key count');
}

#------------------------------------------------------------------------
# constructor — object with as_list() method
#------------------------------------------------------------------------

{
    package MyListObj;
    sub new { bless [ @_[1..$#_] ], $_[0] }
    sub as_list { return $_[0] }

    package main;

    my $obj = MyListObj->new('x', 'y', 'z');
    my $iter = Template::Iterator->new($obj);
    ok(defined $iter, 'constructor accepts object with as_list()');

    my $val = $iter->get_first();
    is($val, 'x', 'as_list object: first item correct');
    is($iter->size(), 3, 'as_list object: size correct');
}

#------------------------------------------------------------------------
# constructor — blessed array without as_list() (wrapped in list)
#------------------------------------------------------------------------

{
    package BlessedArray;
    sub new { bless [ @_[1..$#_] ], $_[0] }

    package main;

    my $obj = BlessedArray->new('p', 'q');
    my $iter = Template::Iterator->new($obj);

    my $val = $iter->get_first();
    is(ref $val, 'BlessedArray', 'blessed array without as_list: item is the object itself');
    is($iter->size(), 1, 'blessed array without as_list: size is 1 (wrapped)');
}

#------------------------------------------------------------------------
# constructor — single scalar (coerced to one-element list)
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new('solo');
    my $val = $iter->get_first();
    is($val, 'solo', 'single scalar: first item correct');
    is($iter->size(), 1, 'single scalar: size is 1');
    is($iter->first(), 1, 'single scalar: first flag set');
    is($iter->last(), 1, 'single scalar: last flag set (only item)');
}

#------------------------------------------------------------------------
# constructor — no argument (defaults to empty list)
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new();
    my ($val, $err) = $iter->get_first();
    ok(!defined $val, 'no argument: get_first returns undef');
    is($err, Template::Constants::STATUS_DONE, 'no argument: STATUS_DONE');
}

#------------------------------------------------------------------------
# constructor — undef (defaults to empty list)
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new(undef);
    my ($val, $err) = $iter->get_first();
    ok(!defined $val, 'undef argument: get_first returns undef');
    is($err, Template::Constants::STATUS_DONE, 'undef argument: STATUS_DONE');
}

#------------------------------------------------------------------------
# constructor — empty array
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([]);
    my ($val, $err) = $iter->get_first();
    ok(!defined $val, 'empty array: get_first returns undef');
    is($err, Template::Constants::STATUS_DONE, 'empty array: STATUS_DONE');
}

#------------------------------------------------------------------------
# constructor — empty hash
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new({});
    my ($val, $err) = $iter->get_first();
    ok(!defined $val, 'empty hash: get_first returns undef');
    is($err, Template::Constants::STATUS_DONE, 'empty hash: STATUS_DONE');
}

#------------------------------------------------------------------------
# get_first — counter and flag initialization
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'a', 'b', 'c' ]);
    $iter->get_first();

    is($iter->index(), 0, 'get_first: index is 0');
    is($iter->count(), 1, 'get_first: count is 1');
    is($iter->size(),  3, 'get_first: size is 3');
    is($iter->first(), 1, 'get_first: first flag is 1');
    is($iter->last(),  0, 'get_first: last flag is 0 (not last)');
}

#------------------------------------------------------------------------
# get_first — can be called multiple times (resets iteration)
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 10, 20, 30 ]);
    is($iter->get_first(), 10, 'first call to get_first returns 10');
    is($iter->get_next(),  20, 'get_next returns 20');
    is($iter->get_first(), 10, 'second get_first resets to 10');
    is($iter->index(), 0, 'index reset to 0 after second get_first');
}

#------------------------------------------------------------------------
# get_next — full iteration
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'w', 'x', 'y', 'z' ]);
    $iter->get_first();

    my $val;
    $val = $iter->get_next();
    is($val, 'x', 'get_next: second item');
    is($iter->index(), 1, 'get_next: index is 1');
    is($iter->count(), 2, 'get_next: count is 2');
    is($iter->first(), 0, 'get_next: first flag is 0');
    is($iter->last(),  0, 'get_next: last flag is 0 (not last yet)');

    $val = $iter->get_next();
    is($val, 'y', 'get_next: third item');

    $val = $iter->get_next();
    is($val, 'z', 'get_next: fourth (last) item');
    is($iter->last(), 1, 'get_next: last flag is 1 on final item');

    my ($end_val, $err) = $iter->get_next();
    ok(!defined $end_val, 'get_next: undef after exhaustion');
    is($err, Template::Constants::STATUS_DONE, 'get_next: STATUS_DONE after exhaustion');
}

#------------------------------------------------------------------------
# get_next — warning when called before get_first
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 1, 2, 3 ]);
    my $warning = '';
    local $SIG{__WARN__} = sub { $warning = $_[0] };

    my ($val, $err) = $iter->get_next();
    ok(!defined $val, 'get_next before get_first: returns undef');
    is($err, Template::Constants::STATUS_DONE, 'get_next before get_first: STATUS_DONE');
    like($warning, qr/get_next\(\) called before get_first\(\)/,
         'get_next before get_first: emits warning');
}

#------------------------------------------------------------------------
# get_all — before get_first (auto-initializes)
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'p', 'q', 'r' ]);
    my ($all, $err) = $iter->get_all();
    is(ref $all, 'ARRAY', 'get_all before get_first: returns array ref');
    is(scalar @$all, 3, 'get_all before get_first: contains all items');
    is($all->[0], 'p', 'get_all before get_first: first item correct');
    is($all->[2], 'r', 'get_all before get_first: last item correct');
}

#------------------------------------------------------------------------
# get_all — mid-iteration (returns remaining)
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'a', 'b', 'c', 'd', 'e' ]);
    $iter->get_first();  # a
    $iter->get_next();   # b

    my $rest = $iter->get_all();
    is(scalar @$rest, 3, 'get_all mid-iteration: returns remaining 3 items');
    is($rest->[0], 'c', 'get_all mid-iteration: starts at next item');
    is($rest->[2], 'e', 'get_all mid-iteration: ends at last item');
}

#------------------------------------------------------------------------
# get_all — after exhaustion
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'x' ]);
    $iter->get_first();
    $iter->get_next();  # exhausted

    my ($val, $err) = $iter->get_all();
    ok(!defined $val, 'get_all after exhaustion: returns undef');
    is($err, Template::Constants::STATUS_DONE, 'get_all after exhaustion: STATUS_DONE');
}

#------------------------------------------------------------------------
# get_all — single item list
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'only' ]);
    my ($all, $err) = $iter->get_all();
    is(scalar @$all, 1, 'get_all single item: contains 1 item');
    is($all->[0], 'only', 'get_all single item: value correct');
    ok(!$err, 'get_all single item: no error');
}

#------------------------------------------------------------------------
# prev / next accessors (via AUTOLOAD)
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'a', 'b', 'c' ]);

    $iter->get_first();
    ok(!defined $iter->prev(), 'prev: undef on first item');
    is($iter->next(), 'b', 'next: returns second item on first');

    $iter->get_next();
    is($iter->prev(), 'a', 'prev: returns first item on second');
    is($iter->next(), 'c', 'next: returns third item on second');

    $iter->get_next();
    is($iter->prev(), 'b', 'prev: returns second item on third');
    ok(!defined $iter->next(), 'next: undef on last item');
}

#------------------------------------------------------------------------
# odd / even / parity
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'a', 'b', 'c', 'd' ]);

    $iter->get_first();  # count=1
    is($iter->odd(),    1,     'count 1: odd is 1');
    is($iter->even(),   0,     'count 1: even is 0');
    is($iter->parity(), 'odd', 'count 1: parity is odd');

    $iter->get_next();   # count=2
    is($iter->odd(),    0,      'count 2: odd is 0');
    is($iter->even(),   1,      'count 2: even is 1');
    is($iter->parity(), 'even', 'count 2: parity is even');

    $iter->get_next();   # count=3
    is($iter->parity(), 'odd', 'count 3: parity is odd');

    $iter->get_next();   # count=4
    is($iter->parity(), 'even', 'count 4: parity is even');
}

#------------------------------------------------------------------------
# number() — backward-compatible alias for count()
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'a', 'b' ]);
    $iter->get_first();
    is($iter->number(), 1, 'number() returns count (1) on first item');
    $iter->get_next();
    is($iter->number(), 2, 'number() returns count (2) on second item');
}

#------------------------------------------------------------------------
# AUTOLOAD — NUMBER alias in AUTOLOAD resolves to COUNT
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'a', 'b', 'c' ]);
    $iter->get_first();
    $iter->get_next();

    # AUTOLOAD uppercases the method name and looks it up in $self
    is($iter->max(), 2, 'AUTOLOAD: max() returns 2 for 3-item list');
}

#------------------------------------------------------------------------
# single-item list — first and last both true
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 'alone' ]);
    my $val = $iter->get_first();
    is($val, 'alone', 'single item: value correct');
    is($iter->first(), 1, 'single item: first is 1');
    is($iter->last(),  1, 'single item: last is 1');
    is($iter->size(),  1, 'single item: size is 1');
    is($iter->index(), 0, 'single item: index is 0');
    is($iter->count(), 1, 'single item: count is 1');
}

#------------------------------------------------------------------------
# hash iteration — verify full traversal via templates
#------------------------------------------------------------------------

{
    my $hash = { zz => 'last', aa => 'first', mm => 'middle' };
    my $iter = Template::Iterator->new($hash);

    my @keys;
    my $item = $iter->get_first();
    while (defined $item) {
        push @keys, $item->{key};
        ($item, my $err) = $iter->get_next();
        last if $err;
    }
    is_deeply(\@keys, [ 'aa', 'mm', 'zz' ],
              'hash iteration: keys sorted alphabetically');
}

#------------------------------------------------------------------------
# numeric data — zeros and negative numbers
#------------------------------------------------------------------------

{
    my $iter = Template::Iterator->new([ 0, -1, 0.5 ]);
    my $val = $iter->get_first();
    is($val, 0, 'numeric: zero as first item');
    $val = $iter->get_next();
    is($val, -1, 'numeric: negative number');
    $val = $iter->get_next();
    is($val, 0.5, 'numeric: fractional number');
}

#------------------------------------------------------------------------
# mixed data types
#------------------------------------------------------------------------

{
    my $ref = { nested => 1 };
    my $iter = Template::Iterator->new([ 'text', 42, undef, $ref, [ 'inner' ] ]);
    my $val = $iter->get_first();
    is($val, 'text', 'mixed: string');

    $val = $iter->get_next();
    is($val, 42, 'mixed: number');

    $val = $iter->get_next();
    ok(!defined $val, 'mixed: undef element');

    $val = $iter->get_next();
    is_deeply($val, { nested => 1 }, 'mixed: hash ref element');

    $val = $iter->get_next();
    is_deeply($val, [ 'inner' ], 'mixed: array ref element');
}
