#============================================================= -*-perl-*-
#
# t/truncate_cer.t
#
# Tests for truncate filter with HTML Character Entity Reference awareness.
# Ensures that CERs like &hellip; &#8230; &#x2026; in the suffix (and in
# the input text) are counted as single visual characters.
#
# Related: https://github.com/abw/Template2/pull/188
#          RT#95707
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Template;
use Template::Filters;
use Test::More;

my $tt = Template->new({ INTERPOLATE => 0 });

my @tests = (
    #--------------------------------------------------------------------
    # Named entity in suffix (&hellip;)
    #--------------------------------------------------------------------
    {
        name   => 'named entity suffix: &hellip; counts as 1 char',
        input  => 'I have much to say on this matter that has previously been said.',
        tmpl   => '[% text | truncate(27, "&hellip;") %]',
        expect => 'I have much to say on this&hellip;',
    },
    {
        name   => 'named entity suffix: &amp; counts as 1 char',
        input  => 'The quick brown fox jumps over the lazy dog.',
        tmpl   => '[% text | truncate(15, "&amp;more") %]',
        # suffix visual length: &amp; (1) + more (4) = 5
        # text visual chars: 15 - 5 = 10 → "The quick "
        expect => 'The quick &amp;more',
    },

    #--------------------------------------------------------------------
    # Numeric (decimal) entity in suffix (&#8230;)
    #--------------------------------------------------------------------
    {
        name   => 'decimal entity suffix: &#8230; counts as 1 char',
        input  => 'I have much to say on this matter that has previously been said.',
        tmpl   => '[% text | truncate(27, "&#8230;") %]',
        expect => 'I have much to say on this&#8230;',
    },

    #--------------------------------------------------------------------
    # Numeric (hex) entity in suffix (&#x2026;)
    #--------------------------------------------------------------------
    {
        name   => 'hex entity suffix: &#x2026; counts as 1 char',
        input  => 'I have much to say on this matter that has previously been said.',
        tmpl   => '[% text | truncate(27, "&#x2026;") %]',
        expect => 'I have much to say on this&#x2026;',
    },

    #--------------------------------------------------------------------
    # Plain suffix (no entities) — regression check
    #--------------------------------------------------------------------
    {
        name   => 'plain suffix: ... still works (3 chars)',
        input  => 'The cat sat on the mat and wondered.',
        tmpl   => '[% text | truncate(10) %]',
        expect => 'The cat...',
    },
    {
        name   => 'no truncation needed',
        input  => 'Short',
        tmpl   => '[% text | truncate(10) %]',
        expect => 'Short',
    },
    {
        name   => 'exact length — no truncation',
        input  => 'Hello World',
        tmpl   => '[% text | truncate(11) %]',
        expect => 'Hello World',
    },
    {
        name   => 'len less than suffix — suffix itself truncated',
        input  => 'Hello World',
        tmpl   => '[% text | truncate(2) %]',
        expect => '..',
    },

    #--------------------------------------------------------------------
    # Multiple entities in suffix
    #--------------------------------------------------------------------
    {
        name   => 'two entities in suffix count as 2 chars',
        input  => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        tmpl   => '[% text | truncate(10, "&lt;&gt;") %]',
        expect => 'ABCDEFGH&lt;&gt;',
    },

    #--------------------------------------------------------------------
    # Mixed plain + entity chars in suffix
    #--------------------------------------------------------------------
    {
        name   => 'mixed suffix: "...&hellip;" counts as 4 chars (3 dots + 1 entity)',
        input  => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        tmpl   => '[% text | truncate(10, "...&hellip;") %]',
        expect => 'ABCDEF...&hellip;',
    },

    #--------------------------------------------------------------------
    # Entity in input text — should not be split
    #--------------------------------------------------------------------
    {
        name   => 'entity in input text not split mid-reference',
        input  => 'AB&amp;CDEFGHIJ',
        tmpl   => '[% text | truncate(5, "...") %]',
        # visual: A B &amp; C D E F G H I J = 11 visual chars
        # truncate to 5 visual: 2 text + "..." = 5? No: 5 - 3 = 2 visual chars of text
        # visual chars: A, B → "AB..."
        expect => 'AB...',
    },
    {
        name   => 'entity in input text counted as 1 visual char',
        input  => 'A&amp;B&lt;C&gt;DEFGHIJKLMNO',
        tmpl   => '[% text | truncate(6, "...") %]',
        # visual: A &amp; B &lt; C &gt; D E F G H I J K L M N O = 18 visual chars
        # truncate to 6: 6 - 3 = 3 visual chars of text
        # A, &amp;, B → "A&amp;B..."
        expect => 'A&amp;B...',
    },
    {
        name   => 'input with entity exactly at boundary',
        input  => 'ABCD&hellip;FGHIJ',
        tmpl   => '[% text | truncate(7, "...") %]',
        # visual: A B C D &hellip; F G H I J = 10 visual chars
        # truncate to 7: 7 - 3 = 4 visual chars of text
        # A, B, C, D → "ABCD..."
        expect => 'ABCD...',
    },
    {
        name   => 'input short enough with entities — no truncation',
        input  => 'A&amp;B',
        tmpl   => '[% text | truncate(10) %]',
        # visual length = 3, less than 10
        expect => 'A&amp;B',
    },

    #--------------------------------------------------------------------
    # Edge cases
    #--------------------------------------------------------------------
    {
        name   => 'empty string — no truncation',
        input  => '',
        tmpl   => '[% text | truncate(10) %]',
        expect => '',
    },
    {
        name   => 'entity-only suffix with len=1',
        input  => 'ABCDEFGHIJ',
        tmpl   => '[% text | truncate(1, "&hellip;") %]',
        # &hellip; is 1 visual char, len=1, so no room for text
        expect => '&hellip;',
    },
    {
        name   => 'ampersand not part of entity — counts normally',
        input  => 'Tom & Jerry go to the park and have fun',
        tmpl   => '[% text | truncate(15, "...") %]',
        # "Tom & Jerry " = 12 chars (no entity), "..." = 3 → 15
        expect => 'Tom & Jerry ...',
    },
    {
        name   => 'incomplete entity reference in input — not treated as CER',
        input  => 'AB&notanentity CDEFGH',
        tmpl   => '[% text | truncate(10, "...") %]',
        # "&notanentity" without semicolon is NOT a CER, counts as individual chars
        expect => 'AB&nota...',
    },
);

plan tests => scalar @tests;

for my $t (@tests) {
    my $output = '';
    $tt->process(\$t->{tmpl}, { text => $t->{input} }, \$output)
        || die $tt->error();
    is($output, $t->{expect}, $t->{name});
}
