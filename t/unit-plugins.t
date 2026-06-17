#!/usr/bin/perl -w
#
# t/unit-plugins.t
#
# Unit tests for Template::Plugins — constructor, fetch, _load, FACTORY cache,
# TOLERANT, LOAD_PERL, PLUGIN_BASE resolution, custom PLUGINS map, CODE factory.
#

use strict;
use lib qw( ./lib ../lib ./t/test/plugin ../t/test/plugin );
use Test::More;

use Template::Plugins;
use Template::Constants qw( STATUS_DECLINED STATUS_ERROR );

#========================================================================
# Mock context (plugins receive $context as first arg)
#========================================================================

package MockContext;
sub new { bless {}, shift }

package main;

my $ctx = MockContext->new;

#========================================================================
# Helper: a minimal TT-plugin package we define inline
#========================================================================

package TestPlugin::Greet;
use base 'Template::Plugin';
sub new {
    my ($class, $context, $greeting) = @_;
    bless { greeting => $greeting // 'hello' }, $class;
}
sub greet { $_[0]->{greeting} }

package TestPlugin::Fails;
use base 'Template::Plugin';
sub new { return undef }  # new() returns undef → die path in fetch()
sub error { 'Fails plugin error' }

package TestPlugin::Dies;
use base 'Template::Plugin';
sub new { die "Dies plugin exploded\n" }

package TestPlugin::Proto;    # prototype / singleton factory
use base 'Template::Plugin';
my $instance;
sub load    { $instance //= bless {}, $_[0]; $instance }
sub new     { $_[0] }        # prototype new() returns itself
sub is_proto { 1 }

package TestPlugin::CodeFactory;   # tests CODE factory branch
use base 'Template::Plugin';

package main;

#========================================================================
# 1. Constructor
#========================================================================

{
    my $p = Template::Plugins->new({});
    isa_ok($p, 'Template::Plugins', 'bare constructor');
    ok(!$p->error, 'no error after bare constructor');
}

{
    my $p = Template::Plugins->new({ TOLERANT => 1 });
    ok($p->{TOLERANT}, 'TOLERANT flag stored');
}

{
    my $p = Template::Plugins->new({ LOAD_PERL => 1 });
    ok($p->{LOAD_PERL}, 'LOAD_PERL flag stored');
}

# PLUGIN_BASE scalar → coerced to array
{
    my $p = Template::Plugins->new({ PLUGIN_BASE => 'My::Namespace' });
    ok(grep { $_ eq 'My::Namespace' } @{ $p->{PLUGIN_BASE} },
        'scalar PLUGIN_BASE ends up in PLUGIN_BASE array');
    ok(grep { $_ eq 'Template::Plugin' } @{ $p->{PLUGIN_BASE} },
        'default Template::Plugin still in PLUGIN_BASE');
}

# PLUGIN_BASE array → preserved, default appended
{
    my $p = Template::Plugins->new({ PLUGIN_BASE => ['First::Base', 'Second::Base'] });
    my @bases = @{ $p->{PLUGIN_BASE} };
    is($bases[0], 'First::Base',  'first custom base retained');
    is($bases[1], 'Second::Base', 'second custom base retained');
    is($bases[2], 'Template::Plugin', 'default base appended');
}

# PLUGINS config merged with STD_PLUGINS
{
    my $p = Template::Plugins->new({
        PLUGINS => { myplug => 'Some::Module' },
    });
    is($p->{PLUGINS}{myplug}, 'Some::Module', 'custom plugin mapping stored');
    ok(exists $p->{PLUGINS}{html}, 'std plugin html still present after custom PLUGINS merge');
}

# PLUGIN_FACTORY pre-populates FACTORY
{
    my $code = sub { bless {}, 'Fake' };
    my $p = Template::Plugins->new({ PLUGIN_FACTORY => { prefab => $code } });
    is($p->{FACTORY}{prefab}, $code, 'PLUGIN_FACTORY pre-populates FACTORY cache');
}

#========================================================================
# 2. fetch() — successful plugin load via PLUGINS map
#========================================================================

{
    my $p = Template::Plugins->new({
        PLUGINS => { greet => 'TestPlugin::Greet' },
    });

    my $obj = $p->fetch('greet', ['hello world'], $ctx);
    isa_ok($obj, 'TestPlugin::Greet', 'fetch returns plugin object');
    is($obj->greet, 'hello world', 'plugin received constructor arg');
}

# args default to [] when undef passed
{
    my $p = Template::Plugins->new({
        PLUGINS => { greet => 'TestPlugin::Greet' },
    });
    my $obj = $p->fetch('greet', undef, $ctx);
    isa_ok($obj, 'TestPlugin::Greet', 'fetch with undef args creates plugin');
    is($obj->greet, 'hello', 'default greeting when no args');
}

#========================================================================
# 3. FACTORY cache — _load() called only once
#========================================================================

{
    my $p = Template::Plugins->new({
        PLUGINS => { greet => 'TestPlugin::Greet' },
    });

    $p->fetch('greet', [], $ctx);
    my $cached = $p->{FACTORY}{greet};
    ok(defined $cached, 'factory cached after first fetch');

    $p->fetch('greet', [], $ctx);
    is($p->{FACTORY}{greet}, $cached, 'factory reference unchanged on second fetch (cache hit)');
}

#========================================================================
# 4. fetch() — new() returns undef → error path
#========================================================================

{
    my $p = Template::Plugins->new({
        PLUGINS => { fails => 'TestPlugin::Fails' },
    });

    my ($result, $status) = $p->fetch('fails', [], $ctx);
    is($status, STATUS_ERROR, 'fetch returns STATUS_ERROR when new() returns undef');
    ok(defined $result && length $result, 'error string returned');
}

# TOLERANT mode converts error to DECLINED
{
    my $p = Template::Plugins->new({
        PLUGINS  => { fails => 'TestPlugin::Fails' },
        TOLERANT => 1,
    });

    my ($result, $status) = $p->fetch('fails', [], $ctx);
    is($status, STATUS_DECLINED, 'TOLERANT: new() returning undef → STATUS_DECLINED');
    ok(!defined $result, 'TOLERANT: result is undef on decline');
}

#========================================================================
# 5. fetch() — new() dies → error path
#========================================================================

{
    my $p = Template::Plugins->new({
        PLUGINS => { dies => 'TestPlugin::Dies' },
    });

    my ($result, $status) = $p->fetch('dies', [], $ctx);
    is($status, STATUS_ERROR, 'fetch returns STATUS_ERROR when new() dies');
    like($result, qr/Dies plugin exploded/, 'die message in error string');
}

# TOLERANT mode converts die to DECLINED
{
    my $p = Template::Plugins->new({
        PLUGINS  => { dies => 'TestPlugin::Dies' },
        TOLERANT => 1,
    });

    my ($result, $status) = $p->fetch('dies', [], $ctx);
    is($status, STATUS_DECLINED, 'TOLERANT: new() die → STATUS_DECLINED');
}

#========================================================================
# 6. CODE factory in FACTORY
#========================================================================

{
    my $calls = 0;
    my $code_factory = sub {
        $calls++;
        return bless { from_code => 1 }, 'TestPlugin::CodeFactory';
    };

    my $p = Template::Plugins->new({
        PLUGIN_FACTORY => { coded => $code_factory },
    });

    my $obj = $p->fetch('coded', [], $ctx);
    isa_ok($obj, 'TestPlugin::CodeFactory', 'CODE factory creates object');
    ok($obj->{from_code}, 'CODE factory closure was called');
    is($calls, 1, 'CODE factory called exactly once');
}

# CODE factory returning undef → error
{
    my $null_factory = sub { return undef };
    my $p = Template::Plugins->new({
        PLUGIN_FACTORY => { nullcode => $null_factory },
    });

    my ($result, $status) = $p->fetch('nullcode', [], $ctx);
    is($status, STATUS_ERROR, 'CODE factory returning undef → STATUS_ERROR');
}

#========================================================================
# 7. Prototype factory (load() returns an object, not a class name)
#========================================================================

{
    my $p = Template::Plugins->new({
        PLUGINS => { proto => 'TestPlugin::Proto' },
    });

    my $obj = $p->fetch('proto', [], $ctx);
    ok($obj->is_proto, 'prototype factory: new() called as object method');
}

#========================================================================
# 8. Unknown plugin → STATUS_DECLINED
#========================================================================

{
    my $p = Template::Plugins->new({});

    my ($result, $status) = $p->fetch('absolutely_nonexistent_xyzzy', [], $ctx);
    is($status, STATUS_DECLINED, 'unknown plugin returns STATUS_DECLINED');
    ok(!defined $result, 'result is undef for declined unknown plugin');
}

#========================================================================
# 9. PLUGIN_BASE search path
#========================================================================

{
    # TestPlugin::Greet is already loaded; PLUGIN_BASE 'TestPlugin' should find it
    my $p = Template::Plugins->new({
        PLUGIN_BASE => 'TestPlugin',
    });

    my $obj = $p->fetch('Greet', ['via base'], $ctx);
    isa_ok($obj, 'TestPlugin::Greet', 'PLUGIN_BASE resolution finds module');
    is($obj->greet, 'via base', 'plugin arg passed correctly via PLUGIN_BASE');
}

# dot-separated name → :: conversion
{
    my $p = Template::Plugins->new({
        PLUGIN_BASE => 'TestPlugin',
    });

    my $obj = $p->fetch('Greet', ['dot form'], $ctx);
    isa_ok($obj, 'TestPlugin::Greet', 'dot-separated name resolves');
}

# case-insensitive PLUGINS lookup
{
    my $p = Template::Plugins->new({
        PLUGINS => { greet => 'TestPlugin::Greet' },
    });

    my $obj = $p->fetch('GREET', [], $ctx);
    isa_ok($obj, 'TestPlugin::Greet', 'case-insensitive plugin name lookup');
}

#========================================================================
# 10. LOAD_PERL fallback — loads a regular Perl module (not TT plugin)
#========================================================================

# Define two plain-Perl packages (not Template::Plugin subclasses).
# Pre-register them in %INC so require() succeeds without hitting disk.

package Plain::Counter;
{
    my $count = 0;
    sub new   { $count++; bless { n => $count }, shift }
    sub count { $_[0]->{n} }
}

package Plain::ArgCapture;
our @CAPTURED;
sub new { shift; @CAPTURED = @_; bless {}, 'Plain::ArgCapture' }

package main;

$INC{'Plain/Counter.pm'}    //= 1;
$INC{'Plain/ArgCapture.pm'} //= 1;

{
    my $p = Template::Plugins->new({ LOAD_PERL => 1 });

    my $obj = $p->fetch('Plain::Counter', [], $ctx);
    isa_ok($obj, 'Plain::Counter', 'LOAD_PERL creates plain Perl module instance');
    is($obj->count, 1, 'Plain module new() called without context arg');
}

# LOAD_PERL factory strips $context from args
{
    my $p = Template::Plugins->new({ LOAD_PERL => 1 });
    $p->fetch('Plain::ArgCapture', ['arg1', 'arg2'], $ctx);

    ok(!grep { ref $_ eq 'MockContext' } @Plain::ArgCapture::CAPTURED,
        'LOAD_PERL: context not passed to plain module new()');
    is_deeply(\@Plain::ArgCapture::CAPTURED, ['arg1', 'arg2'],
        'LOAD_PERL: user args passed through correctly');
}

# LOAD_PERL with non-loadable module → STATUS_ERROR (no file, no package)
{
    my $p = Template::Plugins->new({ LOAD_PERL => 1 });
    my ($result, $status) = $p->fetch('Absolutely::Nonexistent::Module::Xyzzy42', [], $ctx);
    ok($status == STATUS_ERROR || $status == STATUS_DECLINED,
        'LOAD_PERL: unloadable module returns error or declined status');
}

#========================================================================
# 11. STD_PLUGINS — spot-check a few standard entries
#========================================================================

{
    my $p = Template::Plugins->new({});
    is($p->{PLUGINS}{format}, 'Template::Plugin::Format', 'std plugin: format');
    is($p->{PLUGINS}{table},  'Template::Plugin::Table',  'std plugin: table');
    is($p->{PLUGINS}{url},    'Template::Plugin::URL',    'std plugin: url');
}

# Custom PLUGINS override std entry
{
    my $p = Template::Plugins->new({
        PLUGINS => { html => 'My::HTML::Plugin' },
    });
    is($p->{PLUGINS}{html}, 'My::HTML::Plugin',
        'custom PLUGINS entry overrides STD_PLUGINS entry');
}

#========================================================================
# 12. _load() error accumulation — bad module, no TOLERANT
#========================================================================

{
    my $p = Template::Plugins->new({
        PLUGINS => { broken => 'NonExistent::Module::ThatCannot::Load' },
    });

    my ($result, $status) = $p->fetch('broken', [], $ctx);
    is($status, STATUS_ERROR, '_load() failure → STATUS_ERROR without TOLERANT');
    ok(defined $result && length $result, 'error string present on _load failure');
}

{
    my $p = Template::Plugins->new({
        PLUGINS  => { broken => 'NonExistent::Module::ThatCannot::Load' },
        TOLERANT => 1,
    });

    my ($result, $status) = $p->fetch('broken', [], $ctx);
    is($status, STATUS_DECLINED, '_load() failure + TOLERANT → STATUS_DECLINED');
}

#========================================================================
# 13. FACTORY not polluted across separate instances
#========================================================================

{
    my $p1 = Template::Plugins->new({ PLUGINS => { greet => 'TestPlugin::Greet' } });
    my $p2 = Template::Plugins->new({});

    $p1->fetch('greet', [], $ctx);

    ok(!exists $p2->{FACTORY}{greet},
        'factory cache is per-instance, not shared between Plugins objects');
}

#========================================================================
done_testing();
