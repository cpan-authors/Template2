#============================================================= -*-perl-*-
#
# t/set-filter.t
#
# Test that pipe filters work correctly with SET and DEFAULT directives.
# Verifies the fix for GH #174: SET foo = "bar" | filter should apply
# the filter to the value before assignment.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Template::Test;
$Template::Test::DEBUG = 0;

test_expect(\*DATA);

__DATA__

#------------------------------------------------------------------------
# SET with pipe filter (GH #174)
#------------------------------------------------------------------------

-- test --
[% SET foo = "foo bar" | uri %][% foo %]
-- expect --
foo%20bar

-- test --
[% SET foo = "<b>bold</b>" | html %][% foo %]
-- expect --
&lt;b&gt;bold&lt;/b&gt;

-- test --
[% SET foo = "hello world" | upper %][% foo %]
-- expect --
HELLO WORLD

#------------------------------------------------------------------------
# implicit assignment with pipe filter (baseline - should still work)
#------------------------------------------------------------------------

-- test --
[% foo = "foo bar" | uri %][% foo %]
-- expect --
foo%20bar

#------------------------------------------------------------------------
# DEFAULT with pipe filter
#------------------------------------------------------------------------

-- test --
[% DEFAULT foo = "foo bar" | uri %][% foo %]
-- expect --
foo%20bar

-- test --
[% SET foo = "exists"; DEFAULT foo = "new value" | uri %][% foo %]
-- expect --
exists

#------------------------------------------------------------------------
# SET without filter (regression check)
#------------------------------------------------------------------------

-- test --
[% SET foo = "hello" %][% foo %]
-- expect --
hello

-- test --
[% SET foo = 42 %][% foo %]
-- expect --
42

#------------------------------------------------------------------------
# expression with filter
#------------------------------------------------------------------------

-- test --
[% SET foo = "hello" _ " world" | upper %][% foo %]
-- expect --
HELLO WORLD

-- test --
[% name = "a b"; SET foo = name | uri %][% foo %]
-- expect --
a%20b

#------------------------------------------------------------------------
# multiple assignments (filter on last)
#------------------------------------------------------------------------

-- test --
[% SET foo = "hello"; SET bar = "a b" | uri %]foo=[% foo %] bar=[% bar %]
-- expect --
foo=hello bar=a%20b
