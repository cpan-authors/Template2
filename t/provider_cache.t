#============================================================= -*-perl-*-
#
# t/provider_cache.t
#
# Test Template::Provider cache behavior, including edge cases
# for small CACHE_SIZE values.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use File::Temp qw(tempdir);
use File::Spec;
use Test::More;
use Template::Provider;

my $dir = tempdir(CLEANUP => 1);

sub write_template {
    my ($name, $content) = @_;
    my $path = File::Spec->catfile($dir, $name);
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print $fh $content;
    close $fh;
    return $path;
}

write_template('alpha.tt', 'Alpha content');
write_template('beta.tt',  'Beta content');
write_template('gamma.tt', 'Gamma content');

#-----------------------------------------------------------------------
# CACHE_SIZE = 1: the cache holds exactly one compiled template
#-----------------------------------------------------------------------

subtest 'CACHE_SIZE 1 — basic load and eviction' => sub {
    my $provider = Template::Provider->new({
        INCLUDE_PATH => $dir,
        CACHE_SIZE   => 1,
    });

    my ($data, $error) = $provider->fetch('alpha.tt');
    ok($data, 'loaded alpha.tt with CACHE_SIZE=1');
    is($error, undef, 'no error on first load');

    ($data, $error) = $provider->fetch('beta.tt');
    ok($data, 'loaded beta.tt — evicted alpha.tt');
    is($error, undef, 'no error on second load');

    ($data, $error) = $provider->fetch('gamma.tt');
    ok($data, 'loaded gamma.tt — evicted beta.tt');
    is($error, undef, 'no error on third load');
};

subtest 'CACHE_SIZE 1 — reload same template' => sub {
    my $provider = Template::Provider->new({
        INCLUDE_PATH => $dir,
        CACHE_SIZE   => 1,
    });

    my ($data1, $err1) = $provider->fetch('alpha.tt');
    ok($data1, 'first load of alpha.tt');

    my ($data2, $err2) = $provider->fetch('alpha.tt');
    ok($data2, 'second load of alpha.tt (cache hit)');
    is($err2, undef, 'no error on cache hit');
};

subtest 'CACHE_SIZE 1 — alternate between two templates' => sub {
    my $provider = Template::Provider->new({
        INCLUDE_PATH => $dir,
        CACHE_SIZE   => 1,
    });

    for my $i (1..5) {
        my $name = $i % 2 ? 'alpha.tt' : 'beta.tt';
        my ($data, $error) = $provider->fetch($name);
        ok($data, "iteration $i: loaded $name");
        is($error, undef, "iteration $i: no error");
    }
};

#-----------------------------------------------------------------------
# CACHE_SIZE = 2: verify eviction doesn't corrupt the linked list
#-----------------------------------------------------------------------

subtest 'CACHE_SIZE 2 — three templates trigger eviction' => sub {
    my $provider = Template::Provider->new({
        INCLUDE_PATH => $dir,
        CACHE_SIZE   => 2,
    });

    my ($d, $e);
    ($d, $e) = $provider->fetch('alpha.tt');
    ok($d, 'alpha.tt loaded (slot 1/2)');

    ($d, $e) = $provider->fetch('beta.tt');
    ok($d, 'beta.tt loaded (slot 2/2)');

    ($d, $e) = $provider->fetch('gamma.tt');
    ok($d, 'gamma.tt loaded — evicted alpha.tt');
    is($e, undef, 'no error after eviction');

    ($d, $e) = $provider->fetch('alpha.tt');
    ok($d, 'alpha.tt reloaded after eviction');
};

#-----------------------------------------------------------------------
# CACHE_SIZE = 0: caching disabled
#-----------------------------------------------------------------------

subtest 'CACHE_SIZE 0 — caching disabled' => sub {
    my $provider = Template::Provider->new({
        INCLUDE_PATH => $dir,
        CACHE_SIZE   => 0,
    });

    my ($data, $error) = $provider->fetch('alpha.tt');
    ok($data, 'loaded alpha.tt with caching disabled');
    is($error, undef, 'no error');

    ($data, $error) = $provider->fetch('beta.tt');
    ok($data, 'loaded beta.tt with caching disabled');
    is($error, undef, 'no error');
};

#-----------------------------------------------------------------------
# Negative CACHE_SIZE: treated as disabled (0)
#-----------------------------------------------------------------------

subtest 'negative CACHE_SIZE — treated as disabled' => sub {
    my $provider = Template::Provider->new({
        INCLUDE_PATH => $dir,
        CACHE_SIZE   => -1,
    });

    my ($data, $error) = $provider->fetch('alpha.tt');
    ok($data, 'loaded with negative CACHE_SIZE');
    is($error, undef, 'no error');
};

#-----------------------------------------------------------------------
# Template content verification through Template.pm
#-----------------------------------------------------------------------

subtest 'CACHE_SIZE 1 — correct content returned' => sub {
    require Template;
    my $tt = Template->new({
        INCLUDE_PATH => $dir,
        CACHE_SIZE   => 1,
    });

    my $output = '';
    $tt->process('alpha.tt', {}, \$output) or die $tt->error;
    is($output, 'Alpha content', 'alpha.tt content correct');

    $output = '';
    $tt->process('beta.tt', {}, \$output) or die $tt->error;
    is($output, 'Beta content', 'beta.tt content correct after eviction');

    $output = '';
    $tt->process('alpha.tt', {}, \$output) or die $tt->error;
    is($output, 'Alpha content', 'alpha.tt content correct after re-eviction');
};

done_testing();
