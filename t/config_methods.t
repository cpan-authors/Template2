#!/usr/bin/perl -w
#
# t/config_methods.t
#
# Unit tests for Template::Config methods: preload, load, constants, instdir
#

use strict;
use lib qw( ./lib ../lib );
use Test::More tests => 22;

use Template::Config;

my $factory = 'Template::Config';

#------------------------------------------------------------------------
# load — successful module loading
#------------------------------------------------------------------------

{
    my $ok = $factory->load('Template::Stash');
    is($ok, 1, 'load() returns 1 for already-loaded module');

    $ok = $factory->load('Template::Iterator');
    is($ok, 1, 'load() returns 1 for Template::Iterator');

    $ok = $factory->load('Template::Exception');
    is($ok, 1, 'load() returns 1 for Template::Exception');
}

#------------------------------------------------------------------------
# load — module not found
#------------------------------------------------------------------------

{
    my $ok = $factory->load('Template::Completely::Nonexistent::Module::XYZ');
    ok(!$ok, 'load() returns undef for nonexistent module');
    like($factory->error(), qr/failed to load/, 'error message mentions failed to load');
}

#------------------------------------------------------------------------
# preload — loads all standard modules
#------------------------------------------------------------------------

{
    my $ok = $factory->preload();
    is($ok, 1, 'preload() returns 1 on success');

    # verify standard modules are loaded
    ok($INC{'Template/Context.pm'}, 'Template::Context is loaded after preload');
    ok($INC{'Template/Parser.pm'}, 'Template::Parser is loaded after preload');
    ok($INC{'Template/Provider.pm'}, 'Template::Provider is loaded after preload');
    ok($INC{'Template/Filters.pm'}, 'Template::Filters is loaded after preload');
}

#------------------------------------------------------------------------
# preload — with extra modules
#------------------------------------------------------------------------

{
    my $ok = $factory->preload('Template::Document');
    is($ok, 1, 'preload() with extra module returns 1');
    ok($INC{'Template/Document.pm'}, 'extra module loaded after preload');
}

#------------------------------------------------------------------------
# preload — fails on bad module
#------------------------------------------------------------------------

{
    my $ok = $factory->preload('Template::Does::Not::Exist::XYZ');
    ok(!$ok, 'preload() returns undef when extra module fails to load');
}

#------------------------------------------------------------------------
# constants — creates a constants namespace
#------------------------------------------------------------------------

{
    my $constants = $factory->constants({ pi => 3.14159 });
    ok(defined $constants, 'constants() returns a defined value');
    ok(ref $constants, 'constants() returns a reference');
}

#------------------------------------------------------------------------
# constants — usable in template
#------------------------------------------------------------------------

{
    use Template;
    my $tt = Template->new({
        CONSTANTS => { greeting => 'Hello', target => 'World' },
    });

    my $output = '';
    my $ok = $tt->process(\q{[% constants.greeting %] [% constants.target %]}, {}, \$output);
    ok($ok, 'constants work in template processing');
    is($output, 'Hello World', 'constants produce correct output');
}

#------------------------------------------------------------------------
# instdir — with $INSTDIR set
#------------------------------------------------------------------------

{
    local $Template::Config::INSTDIR = '/usr/local/tt2';

    my $result = $factory->instdir();
    is($result, '/usr/local/tt2', 'instdir() returns base directory');

    $result = $factory->instdir('templates');
    is($result, '/usr/local/tt2/templates', 'instdir() appends subdirectory');

    # trailing slash handling
    $Template::Config::INSTDIR = '/usr/local/tt2/';
    $result = $factory->instdir('lib');
    is($result, '/usr/local/tt2/lib', 'instdir() strips trailing slash');
}

#------------------------------------------------------------------------
# instdir — without $INSTDIR set
#------------------------------------------------------------------------

{
    local $Template::Config::INSTDIR = '';
    my $result = $factory->instdir();
    ok(!$result, 'instdir() returns undef when INSTDIR not set');
    like($factory->error(), qr/no installation directory/, 'error mentions no installation directory');
}
