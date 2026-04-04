#============================================================= -*-perl-*-
#
# t/compile_error.t
#
# Test that _load_compiled produces a useful error message when a
# compiled template file fails to load (e.g. syntax error, corrupt
# file).  Prior to the fix, the error message interpolated the
# undefined $compiled variable instead of the file path.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Test::More tests => 3;
use File::Temp qw( tempdir );
use File::Spec;
use Template::Provider;

my $dir = tempdir( CLEANUP => 1 );

# Create a broken compiled template file
my $bad_ttc = File::Spec->catfile($dir, 'broken.ttc');
open my $fh, '>', $bad_ttc or die "Cannot write $bad_ttc: $!";
print $fh "this is not valid Perl;\n";
close $fh;

my $provider = Template::Provider->new({
    INCLUDE_PATH => $dir,
    COMPILE_EXT  => '.ttc',
});

# Call _load_compiled directly on the broken file
my $result = $provider->_load_compiled($bad_ttc);

# _load_compiled returns undef on error and sets $provider->error()
is($result, undef, '_load_compiled returns undef for broken compiled template');

my $error = $provider->error();
ok(defined $error, 'error message is set');

# The error message must contain the file path, not the word "undef"
# or an empty interpolation.  Before the fix, $compiled was undef
# and the message was "compiled template : <perl error>".
like($error, qr/\Q$bad_ttc\E/,
     'error message contains the file path, not undef');
