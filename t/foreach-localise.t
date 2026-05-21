#============================================================= -*-perl-*-
#
# t/foreach-localise.t
#
# Test the FOREACH_LOCALISE option which restores the loop iterator
# variable to its pre-loop value after the loop exits (GH #317).
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Template;
use Template::Test;

my $vars = {
    users  => [
        { id => 'abw', name => 'Andy Wardley' },
        { id => 'sam', name => 'Simon Matthews' },
    ],
    letters => [ 'a', 'b', 'c' ],
};

my $config = {
    FOREACH_LOCALISE => 1,
};

test_expect(\*DATA, $config, $vars);

__DATA__

-- test --
-- name iterator variable restored to original value --
[% x = 'original' -%]
[% FOREACH x = letters %][% x %] [% END -%]
x=[% x %]
-- expect --
a b c x=original

-- test --
-- name iterator variable restored to undef when not previously set --
[% FOREACH z = [10, 20] %][% z %] [% END -%]
z='[% z %]'
-- expect --
10 20 z=''

-- test --
-- name nested loops localise independently --
[% a = 'outer_a'; b = 'outer_b' -%]
[% FOREACH a = [1, 2] %][% FOREACH b = ['x', 'y'] %][% a %][% b %] [% END %][% END -%]
a=[% a %] b=[% b %]
-- expect --
1x 1y 2x 2y a=outer_a b=outer_b

-- test --
-- name hash variable restored after loop over hashes --
[% user = 'fred' -%]
[% FOREACH user = users %][% user.name %] [% END -%]
user=[% user %]
-- expect --
Andy Wardley Simon Matthews user=fred

-- test --
-- name postfix FOREACH also localises --
[% n = 'hello' -%]
[% "$n " FOREACH n = [1, 2, 3] -%]
n=[% n %]
-- expect --
1 2 3 n=hello
