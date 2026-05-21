#!/usr/bin/perl
#
# Test that ttree does not prompt for config file creation when
# --file=FILE or --file FILE is specified on the command line (GH #282).
#

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

eval "use AppConfig";
plan skip_all => "AppConfig not installed" if $@;

plan tests => 4;

use_ok('Template::App::ttree');

my $tmpdir = tempdir(CLEANUP => 1);

# Ensure no default rc file exists so the prompt logic would trigger
local $ENV{HOME} = $tmpdir;

my $ttree = Template::App::ttree->new;
isa_ok($ttree, 'Template::App::ttree');

# With -f, the prompt should be suppressed
{
    local @ARGV = ('-f', "$tmpdir/myconfig");
    my $prompted = 0;
    no warnings 'redefine';
    local *Template::App::ttree::emit_log = sub { $prompted = 1 };
    $ttree->offer_create_a_sample_config_file();
    ok(!$prompted, '-f suppresses config file prompt');
}

# With --file=FILE, the prompt should also be suppressed (GH #282)
{
    local @ARGV = ("--file=$tmpdir/myconfig");
    my $prompted = 0;
    no warnings 'redefine';
    local *Template::App::ttree::emit_log = sub { $prompted = 1 };
    $ttree->offer_create_a_sample_config_file();
    ok(!$prompted, '--file=FILE suppresses config file prompt');
}
