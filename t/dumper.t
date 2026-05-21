#============================================================= -*-perl-*-
#
# t/dumper.t
#
# Test the Dumper plugin.
#
# Written by Simon Matthews <sam@knowledgepool.com>
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
# $Id$
#
#========================================================================

use strict;
use lib qw( ./lib ../lib );
our $DEBUG;
use Template::Test;
$^W = 1;

my $params = {
    'baz' => 'boo',
};

$DEBUG = 0;

test_expect(\*DATA, undef, { params => $params });

#------------------------------------------------------------------------

__DATA__
[% USE Dumper -%]
Dumper

-- expect --
Dumper

-- test --
[% USE Dumper -%]
[% Dumper.dump({ foo = 'bar' }, 'hello' ) -%]

-- expect --
$VAR1 = {
          'foo' => 'bar'
        };
$VAR2 = 'hello';


-- test --
[% USE Dumper -%]
[% Dumper.dump(params) -%]

-- expect --
$VAR1 = {
          'baz' => 'boo'
        };

-- test --
[% USE Dumper -%]
[% Dumper.dump_html(params) -%]

-- expect --
$VAR1 = {<br>
          &#39;baz&#39; =&gt; &#39;boo&#39;<br>
        };<br>

-- test --
[% USE dumper(indent=1, pad='> ', varname="frank") -%]
[% dumper.dump(params) -%]

-- expect --
> $frank1 = {
>   'baz' => 'boo'
> };

-- test --
[% USE dumper(Pad='>> ', Varname="bob") -%]
[% dumper.dump(params) -%]

-- expect --
>> $bob1 = {
>>           'baz' => 'boo'
>>         };

-- test --
[% USE Dumper -%]
[% Dumper.dump(params) -%]

-- expect --
$VAR1 = {
          'baz' => 'boo'
        };


