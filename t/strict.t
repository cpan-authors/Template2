#============================================================= -*-perl-*-
#
# t/strict.t
#
# Test strict mode.
#
# Written by Andy Wardley <abw@wardley.org>
#
# Copyright (C) 1996-2009 Andy Wardley.  All Rights Reserved.
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
#========================================================================

use strict;
use warnings;
use lib qw( ../lib );
use Template;
use Template::Test;

my $template = Template->new(
    STRICT => 1
);

test_expect(
    \*DATA, 
    { STRICT => 1 }, 
    { foo => 10, bar => undef, baz => { boz => undef } }
);

__DATA__
-- test --
-- name defined variable --
[% foo %]
-- expect --
10

-- test --
-- name variable with undefined value --
[% TRY; bar; CATCH; error; END %]
-- expect --
var.undef error - undefined variable: bar

-- test --
-- name dotted variable with undefined value --
[% TRY; baz.boz; CATCH; error; END %]
-- expect --
var.undef error - undefined variable: baz.boz

-- test --
-- name undefined first part of dotted.variable --
[% TRY; wiz.bang; CATCH; error; END %]
-- expect --
var.undef error - undefined variable: wiz.bang

-- test --
-- name undefined second part of dotted.variable --
[% TRY; baz.booze; CATCH; error; END %]
-- expect --
var.undef error - undefined variable: baz.booze

-- test --
-- name dotted.variable with args --
[% TRY; baz(10).booze(20, 'blah', "Foo $foo"); CATCH; error; END %]
-- expect --
var.undef error - undefined variable: baz(10).booze(20, 'blah', 'Foo 10')

-- test --
-- name .defined on defined variable --
[% foo.defined ? 'yes' : 'no' %]
-- expect --
yes

-- test --
-- name .defined on undefined variable (GH #170) --
[% wibble.defined ? 'yes' : 'no' %]
-- expect --
no

-- test --
-- name .defined on undef-valued variable --
[% bar.defined ? 'yes' : 'no' %]
-- expect --
no

-- test --
-- name .defined on nested undefined variable --
[% baz.nope.defined ? 'yes' : 'no' %]
-- expect --
no

-- test --
-- name .defined on nested defined variable --
[% baz.boz.defined ? 'yes' : 'no' %]
-- expect --
no

-- test --
-- name hash.defined(key) with undef value --
[% baz.defined('boz') ? 'yes' : 'no' %]
-- expect --
no

-- test --
-- name undefined var without .defined still throws --
[% TRY; wibble; CATCH; error; END %]
-- expect --
var.undef error - undefined variable: wibble

