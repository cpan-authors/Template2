#!/usr/bin/perl

#============================================================= -*-perl-*-
#
# t/zz-plugin-leak-rt-46691.t
#
# Testcase from RT #46691 aka GH #144
#   view https://github.com/abw/Template2/issues/144
#
# Written by Nicolas R. <atoomic@cpan.org>
#
# Copyright (C) 2018 cPanel Inc.  All Rights Reserved.
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
#========================================================================

use lib qw( t/lib ./lib ../lib ../blib/arch ./test );

use Template;
use Test::More;

use File::Temp qw(tempfile tempdir);

plan( skip_all => "Developer test only - set RELEASE_TESTING=1" ) unless ( $ENV{AUTOMATED_TESTING} or $ENV{RELEASE_TESTING} );

plan tests => 2;

# ------- t1.txt - checkleak template
my $t1 = <<'EOT';
[% USE checkleak %]
test 1: [% name | checkleak %]
[% INCLUDE t2.txt %]
test 3: [% name3 | checkleak %]
EOT

# ------- t2.txt - an included template
my $t2 = <<'EOT';
[% USE checkleak %]
test 2: [% name2 | checkleak %]
EOT

# ------- checkleak.pm a super checkleak custom filter
my $plugin_checkleak = <<'EOT';

package Template::Plugin::checkleak;

use Template::Plugin::Filter;
use base qw( Template::Plugin::Filter );

no warnings;

sub filter {
    my ($self, $text, $args, $conf) = @_;
    return qq|**|.$text.qq|**|;
}

sub init {
    my $self = shift;
    $self->{'_DYNAMIC'}=1;
    my $name = $self->{ _CONFIG }->{ name } || 'checkleak';
    $self->install_filter($name);
    return $self;
}

1;
EOT

my $template_tmpdir = tempdir( CLEANUP => 1 );

write_text( qq[$template_tmpdir/t1.txt], $t1 );
write_text( qq[$template_tmpdir/t2.txt], $t2 );

my $plugindir = tempdir( CLEANUP => 1 );

my $plugin_pm = qq[$plugindir/Template/Plugin/checkleak.pm];

# pretty ugly but only run by authors...
mkdir("$plugindir/Template") && mkdir("$plugindir/Template/Plugin");
die q[Failed to create plugindir] unless -d "$plugindir/Template/Plugin";

write_text( $plugin_pm, $plugin_checkleak );

unshift @INC, $plugindir;
ok eval { do $plugin_pm; 1 }, "can load Template::Plugin::checkleak"
  or die "Failed to load Template::Plugin::checkleak - $@";

# chdir to our temporary folder with templates
chdir($template_tmpdir) or die;

my $tt = Template->new( { 'PLUGIN_BASE' => $plugindir } );

my $out;
$tt->process(
    't1.txt',
    {
        'name'  => 'jason',
        'name2' => 'fred',
        'name3' => 'jim',
    },
    \$out
) || print STDERR $tt->error();

# make sure we can process the template without any issues
#   the original bug was doing a weaken on the plugin itself..
# resulting in not being able to load it a second time
is $out, <<'EXPECT', "Template processed correctly using Plugin checkleak twice";

test 1: **jason**

test 2: **fred**

test 3: **jim**
EXPECT

done_testing;

exit;

sub write_text {    # could also use File::Slurper::write_file ....
    my ( $file, $content ) = @_;

    open( my $fh, '>:raw', $file ) or die $!;
    print {$fh} $content;
    close($fh);
}
