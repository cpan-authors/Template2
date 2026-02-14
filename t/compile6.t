#============================================================= -*-perl-*-
#
# t/compile6.t
#
# Test that when a template source file changes on disk and is
# recompiled via _refresh(), the compiled file on disk is also
# updated (not just the in-memory cache).
#
# This is a regression test for the bug described in:
#   https://github.com/abw/Template2/issues/98
#   https://github.com/abw/Template2/pull/197
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use File::Temp qw( tempdir );
use File::Path qw( mkpath rmtree );
use File::Spec;
use Template;
use Test::More tests => 8;

# Set up temp directories for source and compiled templates
my $srcdir  = tempdir( CLEANUP => 1 );
my $compdir = tempdir( CLEANUP => 1 );

my $src_file  = File::Spec->catfile($srcdir, 'hello.tt');
my $comp_ext  = '.ttc';

# Step 1: Write the initial template source
write_file($src_file, '[% "Hello, original" %]');

# Step 2: Create a Template object with COMPILE_DIR + COMPILE_EXT
my $tt = Template->new({
    INCLUDE_PATH => $srcdir,
    COMPILE_DIR  => $compdir,
    COMPILE_EXT  => $comp_ext,
    STAT_TTL     => 0,  # always stat the file
});
ok($tt, 'Template object created');

# Step 3: Process the template for the first time (triggers _fetch + _compile with filename)
my $output = '';
ok($tt->process('hello.tt', {}, \$output), 'first process succeeds')
    || diag $tt->error;
is($output, 'Hello, original', 'first output is correct');

# Step 4: Verify compiled file was written to disk
my $comp_file = find_compiled_file($compdir, 'hello.tt' . $comp_ext);
ok($comp_file && -f $comp_file, 'compiled file exists on disk after first compile');

# Record the compiled file's content for later comparison
my $compiled_content_v1 = read_file($comp_file);

# Step 5: Modify the source template (with a newer mtime)
# Sleep briefly to ensure the mtime changes
sleep(1);
write_file($src_file, '[% "Hello, updated" %]');

# Step 6: Process the template again — this should trigger _refresh() which recompiles
$output = '';
ok($tt->process('hello.tt', {}, \$output), 'second process succeeds after source change')
    || diag $tt->error;
is($output, 'Hello, updated', 'second output reflects updated source');

# Step 7: Verify the compiled file on disk was also updated
my $compiled_content_v2 = read_file($comp_file);
isnt($compiled_content_v2, $compiled_content_v1,
    'compiled file on disk was updated after source changed');
like($compiled_content_v2, qr/updated/,
    'compiled file contains the new template content');

# -- helpers --

sub write_file {
    my ($path, $content) = @_;
    open(my $fh, '>', $path) or die "Cannot write $path: $!";
    print $fh $content;
    close($fh);
}

sub read_file {
    my ($path) = @_;
    return undef unless $path && -f $path;
    open(my $fh, '<', $path) or die "Cannot read $path: $!";
    local $/;
    my $content = <$fh>;
    close($fh);
    return $content;
}

sub find_compiled_file {
    my ($dir, $suffix) = @_;
    # The compiled file path is $COMPILE_DIR + $src_path + $COMPILE_EXT
    # We need to find it recursively since the full source path is embedded
    my @found;
    _find_files($dir, $suffix, \@found);
    return $found[0];
}

sub _find_files {
    my ($dir, $suffix, $found) = @_;
    opendir(my $dh, $dir) or return;
    while (my $entry = readdir($dh)) {
        next if $entry eq '.' || $entry eq '..';
        my $path = File::Spec->catfile($dir, $entry);
        if (-d $path) {
            _find_files($path, $suffix, $found);
        }
        elsif ($path =~ /\Q$suffix\E$/) {
            push @$found, $path;
        }
    }
    closedir($dh);
}
