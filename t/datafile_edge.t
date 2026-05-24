use strict;
use warnings;
use lib qw( ./lib ./blib/lib ./blib/arch ../lib ../blib/lib ../blib/arch );
use File::Spec;
use Test::More tests => 6;

# MacOS Catalina won't allow Dynaloader to load from relative paths
@INC = map { File::Spec->rel2abs($_) } @INC;

use Template;

my $base = -d 't' ? 't/test/lib' : 'test/lib';

# Test 1: empty file should produce an error without warnings
{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my $tt = Template->new;
    my $output = '';
    my $ok = $tt->process(
        \"[% USE d = datafile('$base/udata_empty') %]loaded",
        {},
        \$output
    );
    ok(!$ok, 'empty datafile returns error');
    like($tt->error(), qr/field names/i, 'error mentions field names');
    is(scalar @warnings, 0, 'no warnings from empty datafile')
        or diag("warnings: @warnings");
}

# Test 2: comment-only file should produce an error without warnings
{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my $tt = Template->new;
    my $output = '';
    my $ok = $tt->process(
        \"[% USE d = datafile('$base/udata_comments') %]loaded",
        {},
        \$output
    );
    ok(!$ok, 'comment-only datafile returns error');
    like($tt->error(), qr/field names/i, 'error mentions field names');
    is(scalar @warnings, 0, 'no warnings from comment-only datafile')
        or diag("warnings: @warnings");
}
