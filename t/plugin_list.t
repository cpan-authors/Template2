#============================================================= -*-perl-*-
#
# t/plugin_list.t
#
# Tests for Template::Plugin::List
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Template::Test;
$^W = 1;

test_expect(\*DATA);

__DATA__

# test basic construction with arrayref argument (#358: variable name mismatch)
-- test --
[% USE l = List([10, 20, 30]) -%]
size: [% l.size %]
-- expect --
size: 3

# test list accessor
-- test --
[% USE l = List([10, 20, 30]) -%]
[% l.list.join(', ') %]
-- expect --
10, 20, 30

# test item accessor
-- test --
[% USE l = List(['a', 'b', 'c']) -%]
[% l.item(0) %] [% l.item(1) %] [% l.item(2) %]
-- expect --
a b c

# test text/stringification with default joint
-- test --
[% USE l = List(['x', 'y', 'z']) -%]
[% l.text %]
-- expect --
x, y, z

# test text with custom joint
-- test --
[% USE l = List(['x', 'y', 'z'], joint => ' - ') -%]
[% l.text %]
-- expect --
x - y - z

# test push (#359: missing comma in CORE::push)
-- test --
[% USE l = List([1, 2]) -%]
[% CALL l.push(3) -%]
[% l.list.join(', ') %]
-- expect --
1, 2, 3

# test unshift (#359: missing comma in CORE::unshift)
-- test --
[% USE l = List([2, 3]) -%]
[% CALL l.unshift(1) -%]
[% l.list.join(', ') %]
-- expect --
1, 2, 3

# test pop
-- test --
[% USE l = List([1, 2, 3]) -%]
[% CALL l.pop -%]
[% l.list.join(', ') %]
-- expect --
1, 2

# test shift
-- test --
[% USE l = List([1, 2, 3]) -%]
[% CALL l.shift -%]
[% l.list.join(', ') %]
-- expect --
2, 3

# test max and size
-- test --
[% USE l = List(['a', 'b', 'c', 'd']) -%]
max: [% l.max %] size: [% l.size %]
-- expect --
max: 3 size: 4

# test empty list
-- test --
[% USE l = List([]) -%]
size: [% l.size %]
-- expect --
size: 0
