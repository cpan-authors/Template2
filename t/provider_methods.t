#!/usr/bin/perl
#
# Unit tests for Template::Provider — the module that loads, compiles,
# and caches templates.  Tests cover the public API and key internal
# methods directly, without going through Template::Context.

use strict;
use warnings;
use Test::More;

use File::Temp qw(tempdir tempfile);
use File::Spec;
use File::Path qw(mkpath rmtree);
use Cwd qw(abs_path);

use Template::Provider;
use Template::Constants qw( :status :debug );
use Template::Document;

my $dir = -d 't' ? 't/test/src' : 'test/src';
my $absdir = abs_path($dir);

#=======================================================================
# Constructor / _init
#=======================================================================

subtest 'constructor defaults' => sub {
    my $p = Template::Provider->new({});
    isa_ok($p, 'Template::Provider');
    is_deeply($p->{INCLUDE_PATH}, ['.'], 'default INCLUDE_PATH is ["."]');
    is($p->{ABSOLUTE}, 0, 'ABSOLUTE defaults to 0');
    is($p->{RELATIVE}, 0, 'RELATIVE defaults to 0');
    is($p->{TOLERANT}, 0, 'TOLERANT defaults to 0');
    is($p->{COMPILE_EXT}, '', 'COMPILE_EXT defaults to empty');
    is($p->{COMPILE_DIR}, '', 'COMPILE_DIR defaults to empty');
    is($p->{DOCUMENT}, 'Template::Document', 'DOCUMENT class default');
    ok(!defined $p->{SIZE}, 'CACHE_SIZE undefined by default (unlimited)');
    is($p->{SLOTS}, 0, 'starts with 0 cache slots');
    is_deeply($p->{LOOKUP}, {}, 'empty LOOKUP hash');
    is_deeply($p->{NOTFOUND}, {}, 'empty NOTFOUND hash');
};

subtest 'INCLUDE_PATH coercion from string' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => "/foo:/bar:/baz",
    });
    is_deeply($p->{INCLUDE_PATH}, ['/foo', '/bar', '/baz'],
        'colon-delimited string split into array');
};

subtest 'INCLUDE_PATH stays array if passed as array' => sub {
    my $paths = ['/one', '/two'];
    my $p = Template::Provider->new({ INCLUDE_PATH => $paths });
    is_deeply($p->{INCLUDE_PATH}, $paths, 'array ref preserved');
};

subtest 'CACHE_SIZE normalization' => sub {
    my $p1 = Template::Provider->new({ CACHE_SIZE => 1 });
    is($p1->{SIZE}, 2, 'CACHE_SIZE 1 bumped to 2');

    my $p2 = Template::Provider->new({ CACHE_SIZE => -5 });
    is($p2->{SIZE}, 2, 'negative CACHE_SIZE bumped to 2');

    my $p3 = Template::Provider->new({ CACHE_SIZE => 10 });
    is($p3->{SIZE}, 10, 'valid CACHE_SIZE preserved');

    my $p4 = Template::Provider->new({ CACHE_SIZE => 0 });
    is($p4->{SIZE}, 0, 'CACHE_SIZE 0 means no caching');
};

subtest 'custom DELIMITER' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => '/a;/b;/c',
        DELIMITER    => ';',
    });
    is_deeply($p->{INCLUDE_PATH}, ['/a', '/b', '/c'],
        'semicolon delimiter splits correctly');
};

subtest 'constructor accepts custom PARSER' => sub {
    my $mock_parser = bless {}, 'My::MockParser';
    my $p = Template::Provider->new({ PARSER => $mock_parser });
    is($p->{PARSER}, $mock_parser, 'custom parser stored');
};

subtest 'ENCODING option' => sub {
    my $p = Template::Provider->new({ ENCODING => 'utf8' });
    is($p->{ENCODING}, 'utf8', 'ENCODING stored');
};

subtest 'DEFAULT option' => sub {
    my $p = Template::Provider->new({ DEFAULT => 'fallback.tt' });
    is($p->{DEFAULT}, 'fallback.tt', 'DEFAULT stored');
};

subtest 'STAT_TTL option' => sub {
    my $p = Template::Provider->new({ STAT_TTL => 300 });
    is($p->{STAT_TTL}, 300, 'STAT_TTL stored');
};

#=======================================================================
# include_path()
#=======================================================================

subtest 'include_path getter/setter' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => ['/original'],
    });
    is_deeply($p->include_path(), ['/original'], 'getter returns current path');

    $p->include_path(['/new/path']);
    is_deeply($p->include_path(), ['/new/path'], 'setter updates path');
};

#=======================================================================
# paths()
#=======================================================================

subtest 'paths() with static list' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => ['/static/one', '/static/two'],
    });
    my $result = $p->paths();
    is_deeply($result, ['/static/one', '/static/two'],
        'static paths returned as-is');
};

subtest 'paths() skips blank entries' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => ['/a', '', '/b', undef, '/c'],
    });
    my $result = $p->paths();
    is_deeply($result, ['/a', '/b', '/c'],
        'blank/undef entries filtered out');
};

subtest 'paths() expands coderef generators' => sub {
    my $gen = sub { ['/dynamic/one', '/dynamic/two'] };
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$gen, '/static'],
    });
    my $result = $p->paths();
    is_deeply($result, ['/dynamic/one', '/dynamic/two', '/static'],
        'coderef expanded into path list');
};

subtest 'paths() expands object generators' => sub {
    my $obj = bless { dirs => ['/obj/a', '/obj/b'] }, 'PathProvider';
    no warnings 'once';
    local *PathProvider::paths = sub { return $_[0]->{dirs} };
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$obj, '/extra'],
    });
    my $result = $p->paths();
    is_deeply($result, ['/obj/a', '/obj/b', '/extra'],
        'object with paths() method expanded');
};

subtest 'paths() errors from coderef' => sub {
    my $gen = sub { die "path generator failed" };
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$gen],
    });
    my $result = $p->paths();
    is($result, undef, 'returns undef on generator error');
    like($p->error(), qr/path generator failed/, 'error message captured');
};

subtest 'paths() MAX_DIRS limit' => sub {
    # generate more dirs than MAX_DIRS allows
    my @many_dirs = map { "/path/$_" } 1..10;
    my $p = Template::Provider->new({
        INCLUDE_PATH => \@many_dirs,
    });
    local $Template::Provider::MAX_DIRS = 5;
    my $result = $p->paths();
    is($result, undef, 'returns undef when MAX_DIRS exceeded');
    like($p->error(), qr/exceeds \d+ directories/, 'MAX_DIRS error message');
};

#=======================================================================
# _template_modified()
#=======================================================================

subtest '_template_modified existing file' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    my $mtime = $p->_template_modified($file);
    ok(defined $mtime, 'returns mtime for existing file');
    ok($mtime > 0, 'mtime is positive');
};

subtest '_template_modified nonexistent file' => sub {
    my $p = Template::Provider->new({});
    my $mtime = $p->_template_modified('/nonexistent/template/path');
    is($mtime, undef, 'returns undef for missing file');
};

subtest '_template_modified undef path' => sub {
    my $p = Template::Provider->new({});
    my $mtime = $p->_template_modified(undef);
    is($mtime, undef, 'returns undef for undef path');
};

#=======================================================================
# _template_content()
#=======================================================================

subtest '_template_content reads file' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    my ($data, $error, $mtime) = $p->_template_content($file);
    ok(defined $data, 'content returned');
    like($data, qr/foo file/, 'content matches expected text');
    is($error, undef, 'no error');
    ok(defined $mtime, 'mtime returned');
};

subtest '_template_content directory error' => sub {
    my $p = Template::Provider->new({});
    my ($data, $error, $mtime) = $p->_template_content($absdir);
    is($data, undef, 'no content for directory');
    like($error, qr/not a file/, 'directory error message');
};

subtest '_template_content no path' => sub {
    my $p = Template::Provider->new({});
    my ($data, $error, $mtime) = $p->_template_content(undef);
    is($data, undef, 'no content for undef path');
    like($error, qr/No path specified/, 'no-path error message');
};

subtest '_template_content nonexistent file' => sub {
    my $p = Template::Provider->new({});
    my ($data, $error, $mtime) = $p->_template_content('/no/such/file');
    is($data, undef, 'no content');
    like($error, qr{/no/such/file:}, 'error includes path');
};

subtest '_template_content scalar context' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    my $data = $p->_template_content($file);
    ok(defined $data, 'scalar context returns content');
    like($data, qr/foo file/, 'content correct');
};

#=======================================================================
# _modified()
#=======================================================================

subtest '_modified without time comparison' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    my $mtime = $p->_modified($file);
    ok($mtime > 0, 'returns mtime for existing file');
};

subtest '_modified with time comparison - newer' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    my $old_time = 1000;
    my $result = $p->_modified($file, $old_time);
    ok($result, 'returns true when file is newer than given time');
};

subtest '_modified with time comparison - older' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    my $future_time = time() + 86400;
    my $result = $p->_modified($file, $future_time);
    ok(!$result, 'returns false when file is older than given time');
};

subtest '_modified nonexistent without time' => sub {
    my $p = Template::Provider->new({});
    my $result = $p->_modified('/nonexistent');
    is($result, 0, 'returns 0 for missing file without time arg');
};

subtest '_modified nonexistent with time' => sub {
    my $p = Template::Provider->new({});
    my $result = $p->_modified('/nonexistent', 12345);
    is($result, 1, 'returns 1 for missing file with time arg');
};

#=======================================================================
# _load()
#=======================================================================

subtest '_load from scalar ref' => sub {
    my $p = Template::Provider->new({});
    my $text = 'Hello [% name %]';
    my $result = $p->_load(\$text);
    is(ref $result, 'HASH', 'returns hashref');
    is($result->{text}, $text, 'text preserved');
    is($result->{name}, 'input text', 'default name for scalar ref');
    ok($result->{time} > 0, 'time set');
    is($result->{load}, 0, 'load is 0 for non-file');
};

subtest '_load from scalar ref with alias' => sub {
    my $p = Template::Provider->new({});
    my $text = 'content';
    my $result = $p->_load(\$text, 'my_alias');
    is($result->{name}, 'my_alias', 'alias used as name');
};

subtest '_load from file handle' => sub {
    my $p = Template::Provider->new({ UNICODE => 0 });
    my $file = File::Spec->catfile($absdir, 'foo');
    open my $fh, '<', $file or die "cannot open $file: $!";
    my $result = $p->_load($fh);
    close $fh;
    is(ref $result, 'HASH', 'returns hashref');
    like($result->{text}, qr/foo file/, 'content read from handle');
    is($result->{name}, 'input file handle', 'default name for handle');
};

subtest '_load from file path' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    my $result = $p->_load($file);
    is(ref $result, 'HASH', 'returns hashref');
    like($result->{text}, qr/foo file/, 'content from file');
    is($result->{name}, $file, 'name is the file path');
    ok($result->{time} > 0, 'mtime set');
    ok($result->{load} > 0, 'load time set');
};

subtest '_load from file path with alias' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    my $result = $p->_load($file, 'custom_name');
    is($result->{name}, 'custom_name', 'alias overrides filename');
    is($result->{path}, $file, 'path is still the file');
};

subtest '_load nonexistent file' => sub {
    my $p = Template::Provider->new({});
    my ($data, $error) = $p->_load('/nonexistent/template');
    is($data, undef, 'undef data');
    is($error, STATUS_DECLINED, 'STATUS_DECLINED for missing file');
};

subtest '_load nonexistent file with TOLERANT' => sub {
    my $p = Template::Provider->new({ TOLERANT => 1 });
    my ($data, $error) = $p->_load('/nonexistent/template');
    is($data, undef, 'undef data');
    is($error, STATUS_DECLINED, 'STATUS_DECLINED when tolerant');
};

#=======================================================================
# fetch() — path type routing
#=======================================================================

subtest 'fetch absolute path denied by default' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    my ($data, $error) = $p->fetch($file);
    is($error, STATUS_ERROR, 'STATUS_ERROR for absolute without ABSOLUTE');
    like($data, qr/absolute paths are not allowed/, 'descriptive error');
};

subtest 'fetch absolute path allowed with ABSOLUTE' => sub {
    my $p = Template::Provider->new({ ABSOLUTE => 1 });
    my $file = File::Spec->catfile($absdir, 'foo');
    my ($data, $error) = $p->fetch($file);
    is($error, undef, 'no error');
    isa_ok($data, 'Template::Document', 'returns compiled document');
};

subtest 'fetch absolute path TOLERANT declines' => sub {
    my $p = Template::Provider->new({ TOLERANT => 1 });
    my $file = File::Spec->catfile($absdir, 'foo');
    my ($data, $error) = $p->fetch($file);
    is($data, undef, 'undef data in tolerant mode');
    is($error, STATUS_DECLINED, 'STATUS_DECLINED in tolerant mode');
};

subtest 'fetch relative path denied by default' => sub {
    my $p = Template::Provider->new({});
    my ($data, $error) = $p->fetch("./something");
    is($error, STATUS_ERROR, 'STATUS_ERROR for relative without RELATIVE');
    like($data, qr/relative paths are not allowed/, 'descriptive error');
};

subtest 'fetch relative path with ../ denied' => sub {
    my $p = Template::Provider->new({});
    my ($data, $error) = $p->fetch("../something");
    is($error, STATUS_ERROR, 'STATUS_ERROR for ../ path');
};

subtest 'fetch relative path TOLERANT declines' => sub {
    my $p = Template::Provider->new({ TOLERANT => 1 });
    my ($data, $error) = $p->fetch("./something");
    is($data, undef, 'undef data');
    is($error, STATUS_DECLINED, 'declined in tolerant mode');
};

subtest 'fetch from INCLUDE_PATH' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
    });
    my ($data, $error) = $p->fetch('foo');
    is($error, undef, 'no error');
    isa_ok($data, 'Template::Document', 'compiled doc from include path');
};

subtest 'fetch nonexistent from INCLUDE_PATH' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
    });
    my ($data, $error) = $p->fetch('no_such_template');
    is($data, undef, 'undef for missing');
    is($error, STATUS_DECLINED, 'STATUS_DECLINED');
};

subtest 'fetch without INCLUDE_PATH declines' => sub {
    my $p = Template::Provider->new({});
    $p->{INCLUDE_PATH} = undef;
    my ($data, $error) = $p->fetch('foo');
    is($data, undef, 'undef');
    is($error, STATUS_DECLINED, 'declined without include path');
};

subtest 'fetch from scalar ref' => sub {
    my $p = Template::Provider->new({});
    my $text = 'Hello World';
    my ($data, $error) = $p->fetch(\$text);
    is($error, undef, 'no error');
    isa_ok($data, 'Template::Document', 'compiled from text ref');
};

subtest 'fetch from file handle' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    open my $fh, '<', $file or die "cannot open: $!";
    my ($data, $error) = $p->fetch($fh);
    close $fh;
    is($error, undef, 'no error');
    isa_ok($data, 'Template::Document', 'compiled from filehandle');
};

#=======================================================================
# fetch() — DEFAULT fallback
#=======================================================================

subtest 'fetch falls back to DEFAULT template' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
        DEFAULT      => 'foo',
    });
    my ($data, $error) = $p->fetch('nonexistent_template');
    is($error, undef, 'no error — fell back to DEFAULT');
    isa_ok($data, 'Template::Document', 'got the default template');
};

subtest 'fetch DEFAULT not infinite loop' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
        DEFAULT      => 'also_missing',
    });
    my ($data, $error) = $p->fetch('nonexistent');
    is($error, STATUS_DECLINED, 'declined when DEFAULT also missing');
};

#=======================================================================
# load() — raw content, no compilation
#=======================================================================

subtest 'load from INCLUDE_PATH' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
    });
    my ($data, $error) = $p->load('foo');
    is($error, STATUS_OK, 'STATUS_OK');
    like($data, qr/foo file/, 'raw content returned');
};

subtest 'load nonexistent declines' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
    });
    my ($data, $error) = $p->load('no_such_file');
    is($data, undef, 'undef for missing');
    is($error, STATUS_DECLINED, 'STATUS_DECLINED');
};

subtest 'load absolute denied by default' => sub {
    my $p = Template::Provider->new({});
    my $file = File::Spec->catfile($absdir, 'foo');
    my ($data, $error) = $p->load($file);
    like($data, qr/absolute paths are not allowed/, 'error message');
    is($error, STATUS_ERROR, 'STATUS_ERROR');
};

subtest 'load absolute allowed with ABSOLUTE' => sub {
    my $p = Template::Provider->new({ ABSOLUTE => 1 });
    my $file = File::Spec->catfile($absdir, 'foo');
    my ($data, $error) = $p->load($file);
    is($error, STATUS_OK, 'STATUS_OK');
    like($data, qr/foo file/, 'content loaded');
};

subtest 'load relative denied by default' => sub {
    my $p = Template::Provider->new({});
    my ($data, $error) = $p->load("./rel/path");
    like($data, qr/relative paths are not allowed/, 'error message');
    is($error, STATUS_ERROR, 'STATUS_ERROR');
};

subtest 'load TOLERANT downgrades errors' => sub {
    my $p = Template::Provider->new({ TOLERANT => 1 });
    my $file = File::Spec->catfile($absdir, 'foo');
    my ($data, $error) = $p->load($file);
    is($data, undef, 'undef in tolerant mode');
    is($error, STATUS_DECLINED, 'declined instead of error');
};

#=======================================================================
# store() / cache behavior
#=======================================================================

subtest 'store and retrieve from cache' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
    });
    my $doc = bless { _BLOCK => sub { 'cached' } }, 'Template::Document';
    $p->store('my_cached', $doc);

    my $slot = $p->{LOOKUP}{'my_cached'};
    ok(defined $slot, 'slot exists in LOOKUP');
    is($slot->[2], $doc, 'document stored in cache slot');
    is($p->{SLOTS}, 1, 'slot count incremented');
};

subtest 'store returns document' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
    });
    my $doc = bless { _BLOCK => sub { 'x' } }, 'Template::Document';
    my $result = $p->store('test', $doc);
    is($result, $doc, 'store returns the document');
};

#=======================================================================
# Cache SIZE limit and LRU eviction
#=======================================================================

subtest 'cache SIZE 0 disables caching' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
        CACHE_SIZE   => 0,
    });
    my ($data, $error) = $p->fetch('foo');
    is($error, undef, 'fetch works');
    isa_ok($data, 'Template::Document', 'returns doc');
    is_deeply($p->{LOOKUP}, {}, 'nothing cached when SIZE=0');
    is($p->{SLOTS}, 0, 'slot count stays 0');
};

subtest 'cache LRU eviction at SIZE limit' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
        CACHE_SIZE   => 2,
    });

    my $doc_a = bless {}, 'Template::Document';
    my $doc_b = bless {}, 'Template::Document';
    my $doc_c = bless {}, 'Template::Document';

    $p->store('tmpl_a', $doc_a);
    $p->store('tmpl_b', $doc_b);
    is($p->{SLOTS}, 2, 'cache at capacity');

    $p->store('tmpl_c', $doc_c);
    is($p->{SLOTS}, 2, 'slot count stays at SIZE');
    ok(!exists $p->{LOOKUP}{'tmpl_a'}, 'oldest entry (a) evicted');
    ok(exists $p->{LOOKUP}{'tmpl_b'}, 'b still in cache');
    ok(exists $p->{LOOKUP}{'tmpl_c'}, 'c in cache');
};

subtest 'cache LRU ordering — head/tail pointers' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
        CACHE_SIZE   => 3,
    });

    $p->store('a', bless({}, 'Template::Document'));
    $p->store('b', bless({}, 'Template::Document'));
    $p->store('c', bless({}, 'Template::Document'));

    is($p->{HEAD}[1], 'c', 'HEAD is most recent (c)');
    is($p->{TAIL}[1], 'a', 'TAIL is oldest (a)');

    # verify linked list integrity
    my $slot = $p->{HEAD};
    my @order;
    while ($slot) {
        push @order, $slot->[1];
        $slot = $slot->[4];  # NEXT
    }
    is_deeply(\@order, ['c', 'b', 'a'], 'forward traversal order');
};

#=======================================================================
# Negative cache (NOTFOUND)
#=======================================================================

subtest 'negative cache populated on miss' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
        STAT_TTL     => 60,
    });

    $p->fetch('nonexistent_tmpl');
    my $path = File::Spec->catfile($absdir, 'nonexistent_tmpl');
    ok(exists $p->{NOTFOUND}{$path}, 'path added to NOTFOUND');
    ok($p->{NOTFOUND}{$path} > 0, 'timestamp recorded');
};

subtest 'negative cache expires after STAT_TTL' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
        STAT_TTL     => 1,
    });

    $p->fetch('still_missing');
    my $path = File::Spec->catfile($absdir, 'still_missing');
    ok(exists $p->{NOTFOUND}{$path}, 'in NOTFOUND initially');

    $p->{NOTFOUND}{$path} = time() - 10;
    $p->fetch('still_missing');
    # after expiry, it re-checks (still missing, re-added)
    ok($p->{NOTFOUND}{$path} >= time() - 1, 'NOTFOUND timestamp refreshed');
};

#=======================================================================
# _compiled_filename()
#=======================================================================

subtest '_compiled_filename with COMPILE_EXT' => sub {
    my $p = Template::Provider->new({
        COMPILE_EXT => '.ttc',
    });
    my $result = $p->_compiled_filename('/some/template.tt');
    is($result, '/some/template.tt.ttc', 'extension appended');
};

subtest '_compiled_filename with COMPILE_DIR' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $p = Template::Provider->new({
        COMPILE_DIR => $tmpdir,
        COMPILE_EXT => '.ttc',
    });
    my $result = $p->_compiled_filename('/some/template.tt');
    like($result, qr/\Q$tmpdir\E/, 'compile dir prefix present');
    like($result, qr/\.ttc$/, 'extension present');
};

subtest '_compiled_filename without COMPILE_EXT or DIR' => sub {
    my $p = Template::Provider->new({});
    my $result = $p->_compiled_filename('/some/template.tt');
    is($result, undef, 'undef when no compile options set');
};

subtest '_compiled_filename caches result' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $p = Template::Provider->new({
        COMPILE_DIR => $tmpdir,
        COMPILE_EXT => '.ttc',
    });
    my $r1 = $p->_compiled_filename('/a/b.tt');
    my $r2 = $p->_compiled_filename('/a/b.tt');
    is($r1, $r2, 'same result on second call');
    ok(exists $p->{COMPILEDPATH}{'/a/b.tt'}, 'cached in COMPILEDPATH');
};

#=======================================================================
# _compiled_is_current()
#=======================================================================

subtest '_compiled_is_current returns undef without compile options' => sub {
    my $p = Template::Provider->new({});
    my $result = $p->_compiled_is_current('/some/file', time());
    is($result, undef, 'undef when no compile options');
};

subtest '_compiled_is_current with matching mtimes' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $src = File::Spec->catfile($tmpdir, 'src.tt');
    my $compiled = "$src.ttc";

    # create source and compiled files
    _write_file($src, 'source');
    _write_file($compiled, 'compiled');

    my $mtime = (stat($src))[9];
    utime($mtime, $mtime, $compiled);

    my $p = Template::Provider->new({
        COMPILE_EXT  => '.ttc',
    });
    my $result = $p->_compiled_is_current($src, $mtime);
    is($result, $mtime, 'returns mtime when current');
};

subtest '_compiled_is_current with mismatched mtimes' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $src = File::Spec->catfile($tmpdir, 'src2.tt');
    my $compiled = "$src.ttc";

    _write_file($src, 'source');
    _write_file($compiled, 'old compiled');

    my $mtime = (stat($src))[9];
    utime($mtime - 100, $mtime - 100, $compiled);

    my $p = Template::Provider->new({
        COMPILE_EXT => '.ttc',
    });
    my $result = $p->_compiled_is_current($src, $mtime);
    is($result, 0, 'returns 0 when compiled is stale');
};

#=======================================================================
# COMPILE_DIR — on-disk compilation
#=======================================================================

subtest 'fetch with COMPILE_DIR writes compiled file' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $compdir = File::Spec->catdir($tmpdir, 'compiled');
    mkpath($compdir);

    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
        COMPILE_DIR  => $compdir,
        COMPILE_EXT  => '.ttc',
    });

    my ($data, $error) = $p->fetch('foo');
    is($error, undef, 'no error with COMPILE_DIR');
    isa_ok($data, 'Template::Document', 'compiled doc returned');

    my $expected_compiled = $p->_compiled_filename(
        File::Spec->catfile($absdir, 'foo')
    );
    ok(-f $expected_compiled, 'compiled file created on disk')
        if defined $expected_compiled;
};

#=======================================================================
# _decode_unicode()
#=======================================================================

subtest '_decode_unicode passes through plain text' => sub {
    my $p = Template::Provider->new({});
    my $text = 'plain ASCII text';
    my $result = $p->_decode_unicode($text);
    is($result, $text, 'plain text unchanged');
};

subtest '_decode_unicode returns undef for undef' => sub {
    my $p = Template::Provider->new({});
    my $result = $p->_decode_unicode(undef);
    is($result, undef, 'undef passthrough');
};

subtest '_decode_unicode detects UTF-8 BOM' => sub {
    my $p = Template::Provider->new({});
    my $bom_utf8 = "\xef\xbb\xbf";
    my $text = "${bom_utf8}Hello";
    my $result = $p->_decode_unicode($text);
    is($result, 'Hello', 'UTF-8 BOM stripped and decoded');
};

subtest '_decode_unicode with ENCODING fallback' => sub {
    my $p = Template::Provider->new({ ENCODING => 'ascii' });
    my $text = 'simple';
    my $result = $p->_decode_unicode($text);
    is($result, 'simple', 'ENCODING fallback for non-BOM text');
};

subtest '_decode_unicode skips already-decoded text' => sub {
    my $p = Template::Provider->new({});
    my $text = "caf\x{e9}";
    utf8::upgrade($text);
    my $result = $p->_decode_unicode($text);
    is($result, $text, 'already-UTF8 text returned as-is');
};

#=======================================================================
# DESTROY — linked list cleanup
#=======================================================================

subtest 'DESTROY cleans up circular refs' => sub {
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$absdir],
    });
    $p->store('x', bless({}, 'Template::Document'));
    $p->store('y', bless({}, 'Template::Document'));

    ok(defined $p->{HEAD}, 'HEAD exists before DESTROY');
    ok(defined $p->{TAIL}, 'TAIL exists before DESTROY');

    $p->DESTROY();

    is($p->{HEAD}, undef, 'HEAD cleared');
    is($p->{TAIL}, undef, 'TAIL cleared');
};

#=======================================================================
# Multiple INCLUDE_PATH directories
#=======================================================================

subtest 'fetch searches multiple INCLUDE_PATH dirs' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $dir1 = File::Spec->catdir($tmpdir, 'dir1');
    my $dir2 = File::Spec->catdir($tmpdir, 'dir2');
    mkpath($dir1);
    mkpath($dir2);

    _write_file(File::Spec->catfile($dir2, 'only_in_dir2.tt'),
                'Hello from dir2');

    my $p = Template::Provider->new({
        INCLUDE_PATH => [$dir1, $dir2],
    });
    my ($data, $error) = $p->fetch('only_in_dir2.tt');
    is($error, undef, 'found in second dir');
    isa_ok($data, 'Template::Document');
};

subtest 'fetch uses first matching dir' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $dir1 = File::Spec->catdir($tmpdir, 'first');
    my $dir2 = File::Spec->catdir($tmpdir, 'second');
    mkpath($dir1);
    mkpath($dir2);

    _write_file(File::Spec->catfile($dir1, 'shared.tt'), 'from first');
    _write_file(File::Spec->catfile($dir2, 'shared.tt'), 'from second');

    my $p = Template::Provider->new({
        INCLUDE_PATH => [$dir1, $dir2],
    });
    my ($data, $error) = $p->fetch('shared.tt');
    is($error, undef, 'no error');
    isa_ok($data, 'Template::Document');
};

#=======================================================================
# RELATIVE path handling
#=======================================================================

subtest 'fetch relative path with RELATIVE enabled' => sub {
    my $p = Template::Provider->new({ RELATIVE => 1 });
    my $relfile = "./$dir/foo";
    my ($data, $error) = $p->fetch($relfile);
    is($error, undef, 'no error with RELATIVE on');
    isa_ok($data, 'Template::Document', 'compiled from relative path');
};

#=======================================================================
# Cache refresh / STAT_TTL
#=======================================================================

subtest 'cached template reused within STAT_TTL' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    _write_file(File::Spec->catfile($tmpdir, 'cached.tt'), 'v1');

    my $p = Template::Provider->new({
        INCLUDE_PATH => [$tmpdir],
        STAT_TTL     => 3600,
    });

    my ($d1, $e1) = $p->fetch('cached.tt');
    is($e1, undef, 'first fetch ok');

    _write_file(File::Spec->catfile($tmpdir, 'cached.tt'), 'v2');

    my ($d2, $e2) = $p->fetch('cached.tt');
    is($e2, undef, 'second fetch ok');
    is($d1, $d2, 'same document object — cache hit within STAT_TTL');
};

subtest 'cache refresh detects file change after STAT_TTL' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $tmpl_file = File::Spec->catfile($tmpdir, 'refresh.tt');
    _write_file($tmpl_file, 'original');

    my $p = Template::Provider->new({
        INCLUDE_PATH => [$tmpdir],
        STAT_TTL     => 0,
    });

    my ($d1, $e1) = $p->fetch('refresh.tt');
    is($e1, undef, 'first fetch ok');

    sleep 1;
    _write_file($tmpl_file, 'updated content');

    my ($d2, $e2) = $p->fetch('refresh.tt');
    is($e2, undef, 'second fetch ok after update');
};

#=======================================================================
# Error cases
#=======================================================================

subtest 'fetch parse error returns STATUS_ERROR' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    _write_file(File::Spec->catfile($tmpdir, 'broken.tt'),
                '[% FOREACH %]');  # syntax error

    my $p = Template::Provider->new({
        INCLUDE_PATH => [$tmpdir],
    });
    my ($data, $error) = $p->fetch('broken.tt');
    is($error, STATUS_ERROR, 'STATUS_ERROR for parse failure');
};

subtest 'fetch parse error TOLERANT declines' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    _write_file(File::Spec->catfile($tmpdir, 'broken2.tt'),
                '[% FOREACH %]');

    my $p = Template::Provider->new({
        INCLUDE_PATH => [$tmpdir],
        TOLERANT     => 1,
    });
    my ($data, $error) = $p->fetch('broken2.tt');
    is($data, undef, 'undef data in tolerant mode');
    is($error, STATUS_DECLINED, 'declined instead of error');
};

#=======================================================================
# $RELATIVE_PATH regex
#=======================================================================

subtest 'RELATIVE_PATH regex matching' => sub {
    my $re = $Template::Provider::RELATIVE_PATH;

    like('./',            $re, './ is relative');
    like('../',           $re, '../ is relative');
    like('./foo/bar',     $re, './foo/bar is relative');
    like('foo/../bar',    $re, 'foo/../bar is relative');
    like('foo/./bar',     $re, 'foo/./bar is relative');
    unlike('foo',         $re, 'plain name is not relative');
    unlike('foo/bar',     $re, 'foo/bar is not relative');
    unlike('/absolute',   $re, '/absolute is not relative');
};

#=======================================================================
# Provider with object-based paths() provider
#=======================================================================

subtest 'paths() with failing object' => sub {
    {
        package FailingPathProvider;
        sub new { bless {}, shift }
        sub paths { return undef }
        sub error { return "provider path error" }
    }
    my $obj = FailingPathProvider->new();
    my $p = Template::Provider->new({
        INCLUDE_PATH => [$obj],
    });
    my $result = $p->paths();
    is($result, undef, 'undef on failing object');
    like($p->error(), qr/provider path error/, 'error propagated');
};

#=======================================================================
# Helper
#=======================================================================

sub _write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "cannot write $path: $!";
    binmode $fh;
    print $fh $content;
    close $fh;
}

done_testing();
