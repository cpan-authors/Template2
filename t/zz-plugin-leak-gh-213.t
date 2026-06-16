#!/usr/bin/perl

#============================================================= -*-perl-*-
#
# t/zz-plugin-leak-gh-213.t
#
# Testcase from aka GH #213
#   view https://github.com/abw/Template2/pull/213
#
# Written by Nicolas R. <atoomic@cpan.org>
#
#========================================================================

# stolen from t/filter.t need to refactor
package Tie::File2Str;

sub TIEHANDLE {
    my ( $class, $textref ) = @_;
    bless $textref, $class;
}

sub PRINT {
    my $self = shift;
    $$self .= join( '', @_ );
}

package main;

use lib qw( t/lib ./lib ../lib ../blib/arch ./test );

use Template;
use Test::More;

use File::Temp qw(tempfile tempdir);

plan skip_all => "Developer test only - set RELEASE_TESTING=1"
  unless ( $ENV{AUTOMATED_TESTING} or $ENV{RELEASE_TESTING} );

plan tests => 3;

# ------- t1.txt - checkleak template
my $t1 = <<'EOT';
[%- USE Echo -%]
[% FILTER $Echo %]foo[% END %]
[% FILTER $Echo %]bar[% END %]
EOT

# ------- checkleak.pm a super checkleak custom filter
my $plugin_echo = <<'EOT';

package Template::Plugin::Echo;

use base qw(Template::Plugin::Filter);

sub filter {
        my ($self, $text) = @_;

        return $text . $text;
}

1;
EOT

my $template_tmpdir = tempdir( CLEANUP => 1 );

write_text( qq[$template_tmpdir/t1.txt], $t1 );

my $plugindir = tempdir( CLEANUP => 1 );

my $plugin_pm = qq[$plugindir/Template/Plugin/Echo.pm];

# pretty ugly but only run by authors...
mkdir("$plugindir/Template") && mkdir("$plugindir/Template/Plugin");
die q[Failed to create plugindir] unless -d "$plugindir/Template/Plugin";

write_text( $plugin_pm, $plugin_echo );

unshift @INC, $plugindir;
ok eval { do $plugin_pm; 1 }, "can load Template::Plugin::Echo"
  or die "Failed to load Template::Plugin::Echo - $@";

# chdir to our temporary folder with templates
chdir($template_tmpdir) or die;

my $tt = Template->new( { 'PLUGIN_BASE' => $plugindir } );

my $out;
my $stderr;
{
    local *STDERR;
    tie( *STDERR, "Tie::File2Str", \$stderr );

    $tt->process(
        't1.txt',
        {},
        \$out
    ) || print STDERR "Error: " . $tt->error();

}

# make sure we can process the template without any issues
#   the original bug was doing a weaken on the plugin itself..
# resulting in not being able to load it a second time
is $out,
  <<'EXPECT', "Template processed correctly using Plugin Echo twice";
foofoo
barbar
EXPECT

is $stderr, undef, "no warning from process 'Reference is already weak'";

done_testing;

exit;

END { chdir '/' }    # cd out of the temp dir.

sub write_text {     # could also use File::Slurper::write_file ....
    my ( $file, $content ) = @_;

    open( my $fh, '>:raw', $file ) or die $!;
    print {$fh} $content;
    close($fh);
}
