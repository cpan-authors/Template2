#============================================================= -*-perl-*-
#
# t/plugins_preloaded.t
#
# Test that Template::Plugins correctly handles plugins that are already
# loaded in memory (e.g., bundled/embedded in the same file as the
# calling code), without requiring a separate .pm file on disk.
#
# See: https://github.com/abw/Template2/issues/112
#      https://github.com/abw/Template2/pull/196
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib ../blib/arch );
use Test::More;

use Template;
use Template::Plugin;

#------------------------------------------------------------------------
# Define an inline plugin that has no .pm file on disk.
# This simulates the use case from GH #112: plugins defined inline
# in the application code or bundled in the same file.
#------------------------------------------------------------------------

{
    package My::Inline::Plugin;
    use base 'Template::Plugin';

    sub new {
        my ($class, $context, $value) = @_;
        bless { VALUE => $value || 'default' }, $class;
    }

    sub output {
        my $self = shift;
        return "Inline plugin, value is $self->{VALUE}";
    }
}

{
    package My::Inline::AnotherPlugin;
    use base 'Template::Plugin';

    sub new {
        my ($class, $context) = @_;
        bless {}, $class;
    }

    sub greet {
        return "Hello from inline plugin";
    }
}

#------------------------------------------------------------------------
# Test 1: Plugin registered via PLUGINS hash — should not require a file
#------------------------------------------------------------------------
subtest 'inline plugin via PLUGINS hash' => sub {
    my $tt = Template->new({
        PLUGINS => {
            inline => 'My::Inline::Plugin',
        },
    }) || die Template->error();

    my $input = '[% USE p = inline("test_value") %][% p.output %]';
    my $output = '';
    ok($tt->process(\$input, {}, \$output), 'process inline plugin')
        || diag $tt->error();
    is($output, 'Inline plugin, value is test_value',
        'inline plugin produces correct output');
};

#------------------------------------------------------------------------
# Test 2: Multiple inline plugins via PLUGINS hash
#------------------------------------------------------------------------
subtest 'multiple inline plugins via PLUGINS' => sub {
    my $tt = Template->new({
        PLUGINS => {
            inline  => 'My::Inline::Plugin',
            another => 'My::Inline::AnotherPlugin',
        },
    }) || die Template->error();

    my $input = '[% USE p = inline("42") %][% p.output %] / [% USE a = another %][% a.greet %]';
    my $output = '';
    ok($tt->process(\$input, {}, \$output), 'process multiple inline plugins')
        || diag $tt->error();
    is($output, 'Inline plugin, value is 42 / Hello from inline plugin',
        'both inline plugins work correctly');
};

#------------------------------------------------------------------------
# Test 3: Inline plugin via PLUGIN_BASE — namespace-based lookup
#------------------------------------------------------------------------

# Define a plugin under a custom base namespace
{
    package MyBase::Embedded;
    use base 'Template::Plugin';

    sub new {
        my ($class, $context) = @_;
        bless {}, $class;
    }

    sub output {
        return "embedded via plugin base";
    }
}

subtest 'inline plugin via PLUGIN_BASE' => sub {
    my $tt = Template->new({
        PLUGIN_BASE => 'MyBase',
    }) || die Template->error();

    my $input = '[% USE e = Embedded %][% e.output %]';
    my $output = '';
    ok($tt->process(\$input, {}, \$output), 'process plugin via PLUGIN_BASE')
        || diag $tt->error();
    is($output, 'embedded via plugin base',
        'inline plugin found via PLUGIN_BASE');
};

#------------------------------------------------------------------------
# Test 4: Standard disk-based plugins still work (regression check)
#------------------------------------------------------------------------
subtest 'standard plugins still work' => sub {
    my $tt = Template->new() || die Template->error();

    my $input = '[% USE Table([1, 2, 3, 4], rows=2) %][% Table.row(0).join(",") %]';
    my $output = '';
    ok($tt->process(\$input, {}, \$output), 'process standard Table plugin')
        || diag $tt->error();
    is($output, '1,3', 'standard plugin works as before');
};

#------------------------------------------------------------------------
# Test 5: Plugin that is NOT loaded and has no .pm file should fail
#------------------------------------------------------------------------
subtest 'unknown plugin still fails' => sub {
    my $tt = Template->new({
        PLUGINS => {
            nonexistent => 'My::Nonexistent::Plugin',
        },
    }) || die Template->error();

    my $input = '[% USE nonexistent %]';
    my $output = '';
    ok(!$tt->process(\$input, {}, \$output), 'unloaded plugin fails as expected');
    like($tt->error(), qr/nonexistent|Can't locate/i, 'error message mentions the plugin');
};

#------------------------------------------------------------------------
# Test 6: Verify that the plugin is reused on second fetch (caching)
#------------------------------------------------------------------------
subtest 'plugin caching after first load' => sub {
    my $tt = Template->new({
        PLUGINS => {
            inline => 'My::Inline::Plugin',
        },
    }) || die Template->error();

    my $input = '[% USE p1 = inline("first") %][% p1.output %] / [% USE p2 = inline("second") %][% p2.output %]';
    my $output = '';
    ok($tt->process(\$input, {}, \$output), 'process plugin used twice')
        || diag $tt->error();
    is($output, 'Inline plugin, value is first / Inline plugin, value is second',
        'plugin works on repeated use');
};

#------------------------------------------------------------------------
# Test 7: Non-Template::Plugin class should NOT be skipped
# A class that exists but doesn't inherit from Template::Plugin
# should still go through the require path (and fail if no .pm file)
#------------------------------------------------------------------------
{
    package My::NotAPlugin;
    sub new { bless {}, shift }
}

subtest 'non-Template::Plugin class not treated as preloaded' => sub {
    my $tt = Template->new({
        PLUGINS => {
            notplugin => 'My::NotAPlugin',
        },
    }) || die Template->error();

    my $input = '[% USE notplugin %]';
    my $output = '';
    # This should fail because My::NotAPlugin doesn't inherit Template::Plugin
    # so isa() returns false, and there's no .pm file to require
    ok(!$tt->process(\$input, {}, \$output),
        'non-Template::Plugin class is not skipped');
};

#------------------------------------------------------------------------
# Test 8: Inline plugin with default value
#------------------------------------------------------------------------
subtest 'inline plugin with default value' => sub {
    my $tt = Template->new({
        PLUGINS => {
            inline => 'My::Inline::Plugin',
        },
    }) || die Template->error();

    my $input = '[% USE p = inline %][% p.output %]';
    my $output = '';
    ok($tt->process(\$input, {}, \$output), 'process inline plugin with default')
        || diag $tt->error();
    is($output, 'Inline plugin, value is default',
        'inline plugin with default value works');
};

done_testing();
