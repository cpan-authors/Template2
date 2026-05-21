#============================================================= -*-perl-*-
#
# t/zz-unary-minus-gh-315.t
#
# Test that subtraction expressions work correctly in MACRO arguments
# and other contexts.  Prior to the fix, the tokenizer consumed '-' as
# part of a negative number literal even when it was a subtraction
# operator, causing show(x-2) to silently pass only x.
#
# GH #315: Silent parsing failure when passing expressions to a MACRO
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Template::Test;

test_expect(\*DATA);

__DATA__
# subtraction in MACRO arguments (GH #315)
-- test --
[% MACRO show(n) BLOCK %]([% n %])[% END -%]
[% x = 5 -%]
[% show(x+2) %] [% show(x-2) %] [% show(x*2) %]
-- expect --
(7) (3) (10)

# unary minus as standalone expression
-- test --
[% -2 %]
-- expect --
-2

# unary minus in assignment
-- test --
[% x = -3; x %]
-- expect --
-3

# unary minus in function argument
-- test --
[% MACRO show(n) BLOCK %]([% n %])[% END -%]
[% show(-3) %]
-- expect --
(-3)

# double negation
-- test --
[% - -5 %]
-- expect --
5

# subtraction precedence: minus binds looser than multiply
-- test --
[% 10 - 3 * 2 %]
-- expect --
4

# chained subtraction is left-associative
-- test --
[% 10 - 3 - 2 %]
-- expect --
5

# negative number in a range (regression guard)
-- test --
[% r = [-2..2]; r.join(' ') %]
-- expect --
-2 -1 0 1 2
# negative float
-- test --
[% -2.5 + 1 %]
-- expect --
-1.5

# subtraction after parenthesized expression
-- test --
[% (3 + 2) - 1 %]
-- expect --
4

# mixed unary and binary minus
-- test --
[% x = 10; x - -3 %]
-- expect --
13
