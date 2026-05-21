use strict;
use warnings;
use lib qw( ./lib ./blib/lib ./blib/arch ../lib ../blib/lib ../blib/arch );
use File::Spec;
use Test::More tests => 4;

# MacOS Catalina won't allow Dynaloader to load from relative paths
@INC = map { File::Spec->rel2abs($_) } @INC;

use Template;

my $base = -d 't' ? 't/test/lib' : 'test/lib';

# Test 1: empty file should produce an error, not an infinite loop
{
    my $tt = Template->new;
    my $output = '';
    my $ok = $tt->process(
        \"[% USE d = datafile('$base/udata_empty') %]loaded",
        {},
        \$output
    );
    ok(!$ok, 'empty datafile returns error');
    like($tt->error(), qr/field names/i, 'error mentions field names');
}

# Test 2: comment-only file should produce an error, not an infinite loop
{
    my $tt = Template->new;
    my $output = '';
    my $ok = $tt->process(
        \"[% USE d = datafile('$base/udata_comments') %]loaded",
        {},
        \$output
    );
    ok(!$ok, 'comment-only datafile returns error');
    like($tt->error(), qr/field names/i, 'error mentions field names');
}
