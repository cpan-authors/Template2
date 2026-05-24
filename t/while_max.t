#============================================================= -*-perl-*-
#
# t/while_max.t
#
# Test that WHILE_MAX is respected at runtime (not baked at compile time)
#
# Copyright (C) 2026 Andy Wardley.  All Rights Reserved.
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Test::More tests => 4;
use Template;
use Template::Directive;

my $tmpl_count = <<'TT';
[%- i = 0; TRY; WHILE i < 9999; i = i + 1; END; CATCH while; END; i -%]
TT

my $tmpl_catch = <<'TT';
[%- TRY; WHILE 1; END; CATCH while; error.info; END -%]
TT

# Test 1: WHILE_MAX = 50 limits loop to 50 iterations
{
    local $Template::Directive::WHILE_MAX = 50;
    my $tt  = Template->new();
    my $out = '';
    $tt->process(\$tmpl_count, {}, \$out);
    is($out, '50', 'WHILE_MAX = 50 limits loop to 50 iterations');
}

# Test 2: WHILE_MAX = 200 allows up to 200 iterations
{
    local $Template::Directive::WHILE_MAX = 200;
    my $tt  = Template->new();
    my $out = '';
    $tt->process(\$tmpl_count, {}, \$out);
    is($out, '200', 'WHILE_MAX = 200 limits loop to 200 iterations');
}

# Test 3: error message reflects runtime WHILE_MAX value
{
    local $Template::Directive::WHILE_MAX = 75;
    my $tt  = Template->new();
    my $out = '';
    $tt->process(\$tmpl_catch, {}, \$out);
    like($out, qr/> 75 iterations/, 'error message shows runtime WHILE_MAX = 75');
}

# Test 4: changing WHILE_MAX between runs affects the same Template object
{
    $Template::Directive::WHILE_MAX = 30;
    my $tt  = Template->new();
    my $out = '';
    $tt->process(\$tmpl_count, {}, \$out);
    is($out, '30', 'runtime change to WHILE_MAX = 30 takes effect');
    $Template::Directive::WHILE_MAX = 1000;
}
