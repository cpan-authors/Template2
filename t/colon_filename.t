#============================================================= -*-perl-*-
#
# t/colon_filename.t
#
# Test that template filenames containing colons work correctly
# when PREFIX_MAP is not configured. See GH #111.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use File::Temp qw( tempdir );
use File::Spec;
use Template;
use Test::More;

if ($^O eq 'MSWin32') {
    plan skip_all => 'Colons in filenames not supported on Windows';
}

my $dir = tempdir( CLEANUP => 1 );

my $colon_file = File::Spec->catfile($dir, 'report:summary.tt');
open my $fh, '>', $colon_file or die "Cannot create $colon_file: $!";
print $fh "Hello [% name %]";
close $fh;

my $tt = Template->new({
    INCLUDE_PATH => $dir,
});

my $output = '';
ok($tt->process('report:summary.tt', { name => 'World' }, \$output),
    'process template with colon in filename')
    or diag($tt->error());
is($output, 'Hello World', 'output is correct');

$output = '';
ok($tt->process('report:summary.tt', { name => 'TT' }, \$output),
    'process same template again');
is($output, 'Hello TT', 'output correct on second call');

# INSERT should also work
my $wrapper_file = File::Spec->catfile($dir, 'wrapper.tt');
open $fh, '>', $wrapper_file or die "Cannot create $wrapper_file: $!";
print $fh "[% INSERT 'report:summary.tt' %]";
close $fh;

$output = '';
ok($tt->process('wrapper.tt', {}, \$output),
    'INSERT template with colon in filename')
    or diag($tt->error());
is($output, 'Hello [% name %]', 'INSERT returns raw content');

# PREFIX_MAP should still work when configured
my $alt_dir = tempdir( CLEANUP => 1 );
my $alt_file = File::Spec->catfile($alt_dir, 'summary.tt');
open $fh, '>', $alt_file or die "Cannot create $alt_file: $!";
print $fh "Alt [% name %]";
close $fh;

my $src_prov = Template::Config->provider( INCLUDE_PATH => $dir );
my $alt_prov = Template::Config->provider( INCLUDE_PATH => $alt_dir );

my $tt_prefix = Template->new({
    LOAD_TEMPLATES => [ $src_prov, $alt_prov ],
    PREFIX_MAP => {
        src => '0',
        alt => '1',
    },
});

$output = '';
ok($tt_prefix->process('alt:summary.tt', { name => 'Prefixed' }, \$output),
    'PREFIX_MAP routing still works')
    or diag($tt_prefix->error());
is($output, 'Alt Prefixed', 'PREFIX_MAP selects correct provider');

done_testing();
