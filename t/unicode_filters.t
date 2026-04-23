#============================================================= -*-perl-*-
#
# t/unicode_filters.t
#
# Test that case-changing filters (upper, lower, ucfirst, lcfirst) work
# correctly with Unicode characters and don't produce wide character
# warnings.  See GH #137.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Test::More tests => 10;
use Template;

my $tt = Template->new();

# Latin-1 characters (e.g. accented letters)
{
    my $out;
    $tt->process(
        \"[% FILTER upper %][% s %][% END %]",
        { s => "caf\x{e9}" },
        \$out
    );
    chomp $out;
    is($out, "CAF\x{c9}", 'upper filter handles Latin-1 e-acute');
}

{
    my $out;
    $tt->process(
        \"[% FILTER lower %][% s %][% END %]",
        { s => "CAF\x{c9}" },
        \$out
    );
    chomp $out;
    is($out, "caf\x{e9}", 'lower filter handles Latin-1 E-acute');
}

{
    my $out;
    $tt->process(
        \"[% s | ucfirst %]",
        { s => "\x{e9}cole" },
        \$out
    );
    chomp $out;
    is($out, "\x{c9}cole", 'ucfirst handles Latin-1 e-acute');
}

{
    my $out;
    $tt->process(
        \"[% s | lcfirst %]",
        { s => "\x{c9}COLE" },
        \$out
    );
    chomp $out;
    is($out, "\x{e9}COLE", 'lcfirst handles Latin-1 E-acute');
}

# Wide characters (codepoints > 0xFF) — these triggered the warning in GH #137
{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $out;
    # Cyrillic де (U+0434 U+0435)
    $tt->process(
        \"[% FILTER upper %][% s %][% END %]",
        { s => "\x{434}\x{435}" },
        \$out
    );
    chomp $out;
    is($out, "\x{414}\x{415}", 'upper filter handles Cyrillic');
    is(scalar @warnings, 0, 'no wide character warnings from upper filter');
}

{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $out;
    $tt->process(
        \"[% FILTER lower %][% s %][% END %]",
        { s => "\x{414}\x{415}" },
        \$out
    );
    chomp $out;
    is($out, "\x{434}\x{435}", 'lower filter handles Cyrillic');
    is(scalar @warnings, 0, 'no wide character warnings from lower filter');
}

# ASCII still works as before
{
    my $out;
    $tt->process(
        \"[% FILTER upper %]hello world[% END %]",
        {},
        \$out
    );
    chomp $out;
    is($out, 'HELLO WORLD', 'upper filter still works for ASCII');
}

{
    my $out;
    $tt->process(
        \"[% FILTER lower %]HELLO WORLD[% END %]",
        {},
        \$out
    );
    chomp $out;
    is($out, 'hello world', 'lower filter still works for ASCII');
}
