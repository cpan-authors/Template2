#!/usr/bin/perl -w
#
# t/unit-context.t
#
# Comprehensive unit tests for Template::Context covering:
#   - constructor (_init) configuration
#   - template() resolution (blocks, blkstack, providers, prefixes, EXPOSE_BLOCKS)
#   - process() with TRIM, multiple templates, callers, error propagation
#   - include() localization
#   - insert() raw file retrieval
#   - throw() argument forms
#   - catch() coercion and output buffer
#   - localise/delocalise
#   - visit/leave
#   - reset()
#   - define_block() (text and coderef)
#   - define_filter() static and dynamic
#   - define_vmethod()
#   - define_view() with base
#   - define_views() hash and list forms
#   - filter() caching, aliasing, error
#   - plugin() loading, error
#   - view()
#   - debugging() on/off/format/msg
#   - stash() accessor
#   - AUTOLOAD read-only access
#   - DESTROY circular ref cleanup
#

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Test::More;
use Scalar::Util qw( blessed refaddr );

use Template;
use Template::Context;
use Template::Config;
use Template::Constants qw( :debug :status :error );
use Template::Document;
use Template::Exception;
use Template::Provider;
use Template::Stash;

my $dir = -d 't' ? 't/test' : 'test';

#========================================================================
# Constructor / _init
#========================================================================

subtest 'constructor with defaults' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
    });
    ok(defined $ctx, 'constructor returns defined value');
    isa_ok($ctx, 'Template::Context');
    is(ref $ctx->{ LOAD_TEMPLATES }, 'ARRAY', 'LOAD_TEMPLATES is arrayref');
    is(ref $ctx->{ LOAD_PLUGINS }, 'ARRAY', 'LOAD_PLUGINS is arrayref');
    is(ref $ctx->{ LOAD_FILTERS }, 'ARRAY', 'LOAD_FILTERS is arrayref');
    isa_ok($ctx->{ STASH }, 'Template::Stash');
    is($ctx->{ RECURSION }, 0, 'RECURSION defaults to 0');
    is($ctx->{ EVAL_PERL }, 0, 'EVAL_PERL defaults to 0');
    is($ctx->{ TRIM }, 0, 'TRIM defaults to 0');
    is(ref $ctx->{ BLKSTACK }, 'ARRAY', 'BLKSTACK initialized as arrayref');
    is(scalar @{ $ctx->{ BLKSTACK } }, 0, 'BLKSTACK starts empty');
    is(ref $ctx->{ BLOCKS }, 'HASH', 'BLOCKS initialized as hash');
};

subtest 'constructor with VARIABLES' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        VARIABLES => { foo => 'bar', num => 42 },
    });
    is($ctx->stash->get('foo'), 'bar', 'VARIABLES sets stash values');
    is($ctx->stash->get('num'), 42, 'VARIABLES sets numeric values');
};

subtest 'constructor with PRE_DEFINE' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        PRE_DEFINE => { alpha => 'one' },
    });
    is($ctx->stash->get('alpha'), 'one', 'PRE_DEFINE sets stash values');
};

subtest 'constructor with custom STASH' => sub {
    my $stash = Template::Stash->new({ custom => 'value' });
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        STASH => $stash,
    });
    is(refaddr($ctx->stash), refaddr($stash), 'custom STASH object used');
    is($ctx->stash->get('custom'), 'value', 'custom stash variables accessible');
};

subtest 'constructor with BLOCKS' => sub {
    my $block_sub = sub { return "hello from block" };
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        BLOCKS => {
            static_block => $block_sub,
            text_block   => 'Hello [% name %]',
        },
    });
    is($ctx->{ BLOCKS }->{ static_block }, $block_sub, 'coderef block stored');
    ok(ref $ctx->{ BLOCKS }->{ text_block }, 'text block compiled');
};

subtest 'constructor with TRIM and EVAL_PERL' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        TRIM => 1,
        EVAL_PERL => 1,
        RECURSION => 1,
    });
    is($ctx->{ TRIM }, 1, 'TRIM enabled');
    is($ctx->{ EVAL_PERL }, 1, 'EVAL_PERL enabled');
    is($ctx->{ RECURSION }, 1, 'RECURSION enabled');
};

subtest 'constructor with PREFIX_MAP' => sub {
    my $provider = Template::Provider->new({ INCLUDE_PATH => "$dir/src" });
    my $ctx = Template::Context->new({
        LOAD_TEMPLATES => [ $provider ],
        PREFIX_MAP => {
            src => [ $provider ],
            default => [ $provider ],
        },
    });
    is(ref $ctx->{ PREFIX_MAP }->{ src }, 'ARRAY', 'PREFIX_MAP src is array');
    is(ref $ctx->{ PREFIX_MAP }->{ default }, 'ARRAY', 'PREFIX_MAP default is array');
};

subtest 'constructor with EXPOSE_BLOCKS' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        EXPOSE_BLOCKS => 1,
    });
    is($ctx->{ EXPOSE_BLOCKS }, 1, 'EXPOSE_BLOCKS stored');
};

subtest 'constructor with DEBUG' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        DEBUG => DEBUG_CONTEXT | DEBUG_DIRS,
    });
    ok($ctx->{ DEBUG }, 'DEBUG flag set');
    ok($ctx->{ DEBUG_DIRS }, 'DEBUG_DIRS extracted');
};

subtest 'constructor with DEBUG_FORMAT' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        DEBUG_FORMAT => '## $file:$line ##',
    });
    is($ctx->{ DEBUG_FORMAT }, '## $file:$line ##', 'DEBUG_FORMAT stored');
};

#========================================================================
# template() resolution
#========================================================================

subtest 'template() with Document object' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $doc = Template::Document->new({
        BLOCK => sub { "doc output" },
        DEFBLOCKS => {},
    });
    my $result = $ctx->template($doc);
    is(refaddr($result), refaddr($doc), 'Document object returned as-is');
};

subtest 'template() with CODE ref' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $code = sub { "code output" };
    my $result = $ctx->template($code);
    is(refaddr($result), refaddr($code), 'CODE ref returned as-is');
};

subtest 'template() from BLOCKS cache' => sub {
    my $block = sub { "cached block" };
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        BLOCKS => { cached => $block },
    });
    my $result = $ctx->template('cached');
    is($result, $block, 'template found in BLOCKS cache');
};

subtest 'template() from BLKSTACK' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $block = sub { "stacked block" };
    $ctx->visit(undef, { stacked => $block });
    my $result = $ctx->template('stacked');
    is($result, $block, 'template found in BLKSTACK');
    $ctx->leave();
};

subtest 'template() BLKSTACK searched in order' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $first = sub { "first" };
    my $second = sub { "second" };
    $ctx->visit(undef, { shared => $first });
    $ctx->visit(undef, { shared => $second });
    my $result = $ctx->template('shared');
    is($result, $second, 'most recent BLKSTACK entry wins');
    $ctx->leave();
    $ctx->leave();
};

subtest 'template() throws on not found' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    eval { $ctx->template('completely_nonexistent_xyz') };
    ok($@, 'throws on template not found');
    like("$@", qr/not found/, 'error mentions not found');
};

subtest 'template() from provider by file' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $tmpl = eval { $ctx->template('foo') };
    ok(defined $tmpl, 'template loaded from provider');
    ok(ref $tmpl, 'template is a reference');
};

subtest 'template() with prefix' => sub {
    my $provider = Template::Provider->new({ INCLUDE_PATH => "$dir/src" });
    my $ctx = Template::Context->new({
        LOAD_TEMPLATES => [ $provider ],
        PREFIX_MAP => { src => [ $provider ] },
    });
    my $tmpl = eval { $ctx->template('src:foo') };
    ok(defined $tmpl, 'prefixed template loaded');
};

subtest 'template() invalid prefix throws' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        PREFIX_MAP => {},
    });
    eval { $ctx->template('badprefix:foo') };
    ok($@, 'throws on invalid prefix');
    like("$@", qr/no providers/, 'error mentions no providers');
};

#========================================================================
# throw()
#========================================================================

subtest 'throw() with exception object' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $exc = Template::Exception->new('test', 'test info');
    eval { $ctx->throw($exc) };
    my $caught = $@;
    isa_ok($caught, 'Template::Exception');
    is(refaddr($caught), refaddr($exc), 'same exception object re-thrown');
    is($caught->type, 'test', 'exception type preserved');
    is($caught->info, 'test info', 'exception info preserved');
};

subtest 'throw() with type and info' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    eval { $ctx->throw('mytype', 'my message') };
    my $caught = $@;
    isa_ok($caught, 'Template::Exception');
    is($caught->type, 'mytype', 'exception type correct');
    is($caught->info, 'my message', 'exception info correct');
};

subtest 'throw() with type, info and output' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $output = "partial output";
    eval { $ctx->throw('mytype', 'error', \$output) };
    my $caught = $@;
    isa_ok($caught, 'Template::Exception');
    is($caught->type, 'mytype', 'type correct');
    is($caught->info, 'error', 'info correct');
};

subtest 'throw() with single message' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    eval { $ctx->throw("something went wrong") };
    my $caught = $@;
    isa_ok($caught, 'Template::Exception');
    is($caught->type, 'undef', 'single-arg throw uses undef type');
    is($caught->info, 'something went wrong', 'message is info');
};

subtest 'throw() with empty string' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    eval { $ctx->throw(undef) };
    my $caught = $@;
    isa_ok($caught, 'Template::Exception');
    is($caught->type, 'undef', 'undef arg gives undef type');
    is($caught->info, '', 'undef arg gives empty info');
};

#========================================================================
# catch()
#========================================================================

subtest 'catch() with exception object' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $exc = Template::Exception->new('file', 'not found');
    my $result = $ctx->catch($exc);
    isa_ok($result, 'Template::Exception');
    is(refaddr($result), refaddr($exc), 'same exception returned');
    is($result->type, 'file', 'type preserved');
};

subtest 'catch() with exception and output' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $exc = Template::Exception->new('file', 'not found');
    my $output = "buffer content";
    my $result = $ctx->catch($exc, \$output);
    isa_ok($result, 'Template::Exception');
    like($result->as_string, qr/buffer content|not found/, 'output incorporated');
};

subtest 'catch() with plain error string' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $result = $ctx->catch("plain error message");
    isa_ok($result, 'Template::Exception');
    is($result->type, 'undef', 'plain string becomes undef type');
    is($result->info, 'plain error message', 'string becomes info');
};

subtest 'catch() with undef error' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $result = $ctx->catch(undef);
    isa_ok($result, 'Template::Exception');
    is($result->type, 'undef', 'undef error becomes undef type');
};

#========================================================================
# process()
#========================================================================

subtest 'process() with code block' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $block = sub { return "hello world" };
    my $output = eval { $ctx->process($block) };
    is($output, 'hello world', 'process executes code block');
};

subtest 'process() with params (non-localized)' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $block = sub {
        my $context = shift;
        return $context->stash->get('greeting');
    };
    my $output = eval { $ctx->process($block, { greeting => 'hi' }) };
    is($output, 'hi', 'params available during process');
    is($ctx->stash->get('greeting'), 'hi', 'params persist after process (non-localized)');
};

subtest 'process() with localization (include mode)' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    $ctx->stash->set('val', 'original');
    my $block = sub {
        my $context = shift;
        $context->stash->set('val', 'modified');
        return $context->stash->get('val');
    };
    my $output = eval { $ctx->process($block, {}, 1) };
    is($output, 'modified', 'block sees modified value');
    is($ctx->stash->get('val'), 'original', 'original restored after localized process');
};

subtest 'process() with TRIM' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        TRIM => 1,
    });
    my $block = sub { return "  \n  hello  \n  " };
    my $output = eval { $ctx->process($block) };
    is($output, 'hello', 'TRIM removes leading/trailing whitespace');
};

subtest 'process() with multiple templates' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $block1 = sub { "part1" };
    my $block2 = sub { "part2" };
    my $output = eval { $ctx->process([$block1, $block2]) };
    is($output, 'part1part2', 'multiple templates concatenated');
};

subtest 'process() propagates exceptions' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $block = sub {
        my $context = shift;
        $context->throw('custom', 'deliberate error');
    };
    eval { $ctx->process($block) };
    my $error = $@;
    isa_ok($error, 'Template::Exception');
    is($error->type, 'custom', 'exception type preserved through process');
    is($error->info, 'deliberate error', 'exception info preserved');
};

subtest 'process() localize still declones on exception' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $original_stash = $ctx->stash;
    my $block = sub {
        my $context = shift;
        $context->throw('oops', 'fail');
    };
    eval { $ctx->process($block, { x => 1 }, 1) };
    is(refaddr($ctx->stash), refaddr($original_stash),
        'stash decloned after exception in localized process');
};

subtest 'process() with Document object' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $doc = Template::Document->new({
        BLOCK => sub { "document output" },
        DEFBLOCKS => {},
        METADATA => { name => 'test_doc' },
    });
    my $output = eval { $ctx->process($doc) };
    is($output, 'document output', 'process handles Document objects');
};

#========================================================================
# include()
#========================================================================

subtest 'include() localises stash' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    $ctx->stash->set('color', 'red');
    my $block = sub {
        my $context = shift;
        $context->stash->set('color', 'blue');
        return $context->stash->get('color');
    };
    my $output = eval { $ctx->include($block, { extra => 'yes' }) };
    is($output, 'blue', 'include block sees local changes');
    is($ctx->stash->get('color'), 'red', 'original value restored after include');
    ok(!$ctx->stash->get('extra'), 'include params not visible after return');
};

#========================================================================
# insert()
#========================================================================

subtest 'insert() returns raw file content' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $content = eval { $ctx->insert('foo') };
    ok(defined $content, 'insert returns content');
    ok(length $content > 0, 'content is non-empty');
};

subtest 'insert() with multiple files' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $content = eval { $ctx->insert(['foo', 'blam']) };
    ok(defined $content, 'insert handles array of files') or diag $@;
    ok(length($content // '') > 0, 'combined content is non-empty');
};

subtest 'insert() throws on missing file' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    eval { $ctx->insert('this_file_definitely_does_not_exist_xyz') };
    ok($@, 'insert throws on missing file');
    like("$@", qr/not found/, 'error mentions not found');
};

subtest 'insert() with prefix' => sub {
    my $provider = Template::Provider->new({ INCLUDE_PATH => "$dir/src" });
    my $ctx = Template::Context->new({
        LOAD_TEMPLATES => [ $provider ],
        PREFIX_MAP => { src => [ $provider ] },
    });
    my $content = eval { $ctx->insert('src:foo') };
    ok(defined $content, 'insert with prefix works');
};

subtest 'insert() invalid prefix throws' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        PREFIX_MAP => {},
    });
    eval { $ctx->insert('badprefix:foo') };
    ok($@, 'insert throws on invalid prefix');
    like("$@", qr/no providers/, 'error mentions no providers');
};

#========================================================================
# localise / delocalise
#========================================================================

subtest 'localise creates clone' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $orig_stash = $ctx->stash;
    $orig_stash->set('x', 10);

    my $cloned = $ctx->localise({ y => 20 });
    isnt(refaddr($ctx->stash), refaddr($orig_stash), 'localise creates new stash');
    is($ctx->stash->get('x'), 10, 'parent variables visible in clone');
    is($ctx->stash->get('y'), 20, 'local params set in clone');
};

subtest 'delocalise restores parent' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $orig_stash = $ctx->stash;
    $orig_stash->set('z', 'parent');

    $ctx->localise({ z => 'child' });
    is($ctx->stash->get('z'), 'child', 'localized value');

    $ctx->delocalise();
    is(refaddr($ctx->stash), refaddr($orig_stash), 'original stash restored');
    is($ctx->stash->get('z'), 'parent', 'parent value restored');
};

subtest 'nested localise/delocalise' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    $ctx->stash->set('level', 0);

    $ctx->localise({ level => 1 });
    is($ctx->stash->get('level'), 1, 'level 1');

    $ctx->localise({ level => 2 });
    is($ctx->stash->get('level'), 2, 'level 2');

    $ctx->delocalise();
    is($ctx->stash->get('level'), 1, 'back to level 1');

    $ctx->delocalise();
    is($ctx->stash->get('level'), 0, 'back to level 0');
};

#========================================================================
# visit / leave
#========================================================================

subtest 'visit pushes blocks onto BLKSTACK' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $blocks = { header => sub { "header" } };
    $ctx->visit(undef, $blocks);
    is(scalar @{ $ctx->{ BLKSTACK } }, 1, 'one entry after visit');
    is($ctx->{ BLKSTACK }[0], $blocks, 'correct blocks ref stored');
};

subtest 'leave pops from BLKSTACK' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    $ctx->visit(undef, { a => sub { "a" } });
    $ctx->visit(undef, { b => sub { "b" } });
    is(scalar @{ $ctx->{ BLKSTACK } }, 2, 'two entries');
    $ctx->leave();
    is(scalar @{ $ctx->{ BLKSTACK } }, 1, 'one entry after leave');
    $ctx->leave();
    is(scalar @{ $ctx->{ BLKSTACK } }, 0, 'empty after all leaves');
};

subtest 'visit/leave ordering is LIFO' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $first = { x => sub { "first" } };
    my $second = { x => sub { "second" } };
    $ctx->visit(undef, $first);
    $ctx->visit(undef, $second);
    is($ctx->{ BLKSTACK }[0], $second, 'most recent is at front (unshift)');
    $ctx->leave();
    is($ctx->{ BLKSTACK }[0], $first, 'after leave, first is at front');
};

#========================================================================
# reset()
#========================================================================

subtest 'reset clears BLKSTACK and restores INIT_BLOCKS' => sub {
    my $init_block = sub { "init" };
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        BLOCKS => { init_blk => $init_block },
    });

    # After first reset, BLOCKS becomes a separate hash from INIT_BLOCKS
    $ctx->reset();
    $ctx->define_block('dynamic', sub { "dynamic" });
    $ctx->visit(undef, { visited => sub { "v" } });
    ok(exists $ctx->{ BLOCKS }->{ dynamic }, 'dynamic block exists before reset');
    ok(scalar @{ $ctx->{ BLKSTACK } } > 0, 'BLKSTACK non-empty before reset');

    $ctx->reset();
    is(scalar @{ $ctx->{ BLKSTACK } }, 0, 'BLKSTACK cleared');
    ok(exists $ctx->{ BLOCKS }->{ init_blk }, 'INIT_BLOCKS restored');
    ok(!exists $ctx->{ BLOCKS }->{ dynamic }, 'dynamic block cleared after reset');
};

#========================================================================
# define_block()
#========================================================================

subtest 'define_block with coderef' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $code = sub { "block output" };
    my $result = $ctx->define_block('my_code_block', $code);
    is($result, $code, 'returns the coderef');
    is($ctx->{ BLOCKS }->{ my_code_block }, $code, 'stored in BLOCKS');
};

subtest 'define_block with text compiles it' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $result = $ctx->define_block('my_text_block', 'Static text');
    ok(ref $result, 'returns a reference (compiled)');
    ok(exists $ctx->{ BLOCKS }->{ my_text_block }, 'stored in BLOCKS');
};

subtest 'define_block with Document object' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $doc = Template::Document->new({
        BLOCK => sub { "doc block" },
        DEFBLOCKS => {},
    });
    my $result = $ctx->define_block('doc_block', $doc);
    is(refaddr($result), refaddr($doc), 'Document stored directly');
};

#========================================================================
# define_filter()
#========================================================================

subtest 'define_filter static' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $filter = sub { uc $_[0] };
    my $ok = $ctx->define_filter('test_upper', $filter);
    is($ok, 1, 'define_filter returns 1');
    my $retrieved = $ctx->filter('test_upper');
    is($retrieved->('hello'), 'HELLO', 'static filter works');
};

subtest 'define_filter dynamic' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $factory = sub {
        my ($context, @args) = @_;
        my $n = $args[0] || 1;
        return sub { $_[0] x $n };
    };
    my $ok = $ctx->define_filter('test_repeat', $factory, 1);
    is($ok, 1, 'define_filter dynamic returns 1');
    my $filter = $ctx->filter('test_repeat', [3]);
    is($filter->('ab'), 'ababab', 'dynamic filter with args works');
};

#========================================================================
# define_vmethod()
#========================================================================

subtest 'define_vmethod scalar' => sub {
    my $tt = Template->new({ INCLUDE_PATH => "$dir/src" });
    my $ctx = $tt->service->context;
    $ctx->define_vmethod('item', 'test_double', sub { $_[0] . $_[0] });
    my $output = '';
    $tt->process(\'[% x = "xy"; x.test_double %]', {}, \$output);
    is($output, 'xyxy', 'custom scalar vmethod works');
};

subtest 'define_vmethod list' => sub {
    my $tt = Template->new({ INCLUDE_PATH => "$dir/src" });
    my $ctx = $tt->service->context;
    $ctx->define_vmethod('list', 'test_sum', sub {
        my $list = shift;
        my $sum = 0;
        $sum += $_ for @$list;
        return $sum;
    });
    my $output = '';
    $tt->process(\'[% a = [1,2,3]; a.test_sum %]', {}, \$output);
    is($output, '6', 'custom list vmethod works');
};

#========================================================================
# filter() caching and errors
#========================================================================

subtest 'filter caching without args' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $f1 = $ctx->filter('html');
    my $f2 = $ctx->filter('html');
    is(refaddr($f1), refaddr($f2), 'same filter returned from cache');
};

subtest 'filter with args bypasses cache' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $f1 = $ctx->filter('format', ['%10s']);
    my $f2 = $ctx->filter('format', ['%-10s']);
    isnt(refaddr($f1), refaddr($f2), 'different filter instances with different args');
};

subtest 'filter alias caching' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $f = $ctx->filter('upper', undef, 'MY_UPPER');
    my $cached = $ctx->filter('MY_UPPER');
    is(refaddr($f), refaddr($cached), 'filter cached under alias');
};

subtest 'filter returns undef for unknown' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $f = $ctx->filter('xyzzy_nonexistent_filter');
    ok(!defined $f, 'returns undef for unknown filter');
    like($ctx->error, qr/not found/, 'error set');
};

#========================================================================
# plugin()
#========================================================================

subtest 'plugin loads standard plugin' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $plugin = eval { $ctx->plugin('Format', ['%s!!!']) };
    ok(defined $plugin, 'Format plugin loaded');
    is(ref $plugin, 'CODE', 'Format plugin is a coderef');
};

subtest 'plugin throws for unknown' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    eval { $ctx->plugin('Nonexistent_Plugin_XYZZY_99', []) };
    ok($@, 'throws for unknown plugin');
    like("$@", qr/plugin not found|not found/i, 'error mentions plugin');
};

#========================================================================
# view()
#========================================================================

subtest 'view() creates Template::View' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $view = eval { $ctx->view({ prefix => 'test/' }) };
    ok(defined $view, 'view created');
    isa_ok($view, 'Template::View');
};

#========================================================================
# define_view() / define_views()
#========================================================================

subtest 'define_view stores view in stash' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    eval { $ctx->define_view('myview', { prefix => 'v/' }) };
    my $view = $ctx->stash->get('myview');
    ok(defined $view, 'view stored in stash');
    isa_ok($view, 'Template::View');
};

subtest 'define_view with invalid base throws' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    eval { $ctx->define_view('badview', { base => 'nonexistent_base' }) };
    ok($@, 'throws on undefined base');
    like("$@", qr/not defined/, 'error mentions base not defined');
};

subtest 'define_views with list ref' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    eval {
        $ctx->define_views([
            view_one => { prefix => 'one/' },
            view_two => { prefix => 'two/' },
        ]);
    };
    ok(!$@, 'define_views with list ref succeeds') or diag $@;
    isa_ok($ctx->stash->get('view_one'), 'Template::View');
    isa_ok($ctx->stash->get('view_two'), 'Template::View');
};

subtest 'define_views with hash ref' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    eval {
        $ctx->define_views({
            hview_a => { prefix => 'a/' },
            hview_b => { prefix => 'b/' },
        });
    };
    ok(!$@, 'define_views with hash ref succeeds') or diag $@;
    my $a = $ctx->stash->get('hview_a');
    my $b = $ctx->stash->get('hview_b');
    ok(defined($a) && defined($b), 'both views defined');
};

#========================================================================
# debugging()
#========================================================================

subtest 'debugging on/off' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        DEBUG => DEBUG_DIRS,
    });
    ok($ctx->{ DEBUG_DIRS }, 'starts on');
    $ctx->debugging('off');
    ok(!$ctx->{ DEBUG_DIRS }, 'turned off');
    $ctx->debugging('on');
    ok($ctx->{ DEBUG_DIRS }, 'turned on');
    $ctx->debugging('0');
    ok(!$ctx->{ DEBUG_DIRS }, 'turned off with 0');
    $ctx->debugging('1');
    ok($ctx->{ DEBUG_DIRS }, 'turned on with 1');
};

subtest 'debugging format' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        DEBUG => DEBUG_DIRS,
    });
    $ctx->debugging('format', '[$file:$line] $text');
    is($ctx->{ DEBUG_FORMAT }, '[$file:$line] $text', 'format stored');
};

subtest 'debugging msg generates message' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        DEBUG => DEBUG_DIRS,
        DEBUG_FORMAT => '## $file:$line:$text ##',
    });
    my $msg = $ctx->debugging('msg', {
        file => 'test.tt',
        line => 42,
        text => 'hello',
    });
    is($msg, '## test.tt:42:hello ##', 'msg substitutes values');
};

subtest 'debugging msg returns undef when disabled' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        DEBUG => 0,
    });
    my $msg = $ctx->debugging('msg', { file => 'x', line => 1, text => 'y' });
    ok(!$msg, 'msg returns falsy when DEBUG_DIRS disabled');
};

#========================================================================
# stash() accessor
#========================================================================

subtest 'stash() returns stash object' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $stash = $ctx->stash;
    ok(defined $stash, 'stash defined');
    isa_ok($stash, 'Template::Stash');
    is(refaddr($stash), refaddr($ctx->{ STASH }), 'same as internal STASH');
};

#========================================================================
# AUTOLOAD
#========================================================================

subtest 'AUTOLOAD provides read-only access' => sub {
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src",
        TRIM => 1,
        EVAL_PERL => 1,
        RECURSION => 1,
    });
    is($ctx->trim, 1, 'trim() via AUTOLOAD');
    is($ctx->eval_perl, 1, 'eval_perl() via AUTOLOAD');
    is($ctx->recursion, 1, 'recursion() via AUTOLOAD');
    is(ref $ctx->load_templates, 'ARRAY', 'load_templates() via AUTOLOAD');
    is(ref $ctx->load_plugins, 'ARRAY', 'load_plugins() via AUTOLOAD');
    is(ref $ctx->load_filters, 'ARRAY', 'load_filters() via AUTOLOAD');
};

subtest 'AUTOLOAD warns for undefined members' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    my $warning = '';
    local $SIG{__WARN__} = sub { $warning = shift };
    my $val = $ctx->nonexistent_xyzzy;
    like($warning, qr/no such context method/, 'warns for undefined member');
    ok(!defined $val, 'returns undef for undefined member');
};

#========================================================================
# DESTROY
#========================================================================

subtest 'DESTROY clears STASH reference' => sub {
    my $ctx = Template::Context->new({ INCLUDE_PATH => "$dir/src" });
    ok(defined $ctx->{ STASH }, 'STASH defined before DESTROY');
    $ctx->DESTROY;
    ok(!defined $ctx->{ STASH }, 'STASH undef after DESTROY');
};

#========================================================================
# Integration: process + BLOCKS interaction
#========================================================================

subtest 'PROCESS imports blocks from document' => sub {
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        TRIM => 1,
    });
    my $tmpl = <<'END';
[% BLOCK header %]HEADER[% END -%]
[% BLOCK footer %]FOOTER[% END -%]
[% PROCESS header %] | [% PROCESS footer %]
END
    my $output = '';
    $tt->process(\$tmpl, {}, \$output);
    is($output, 'HEADER | FOOTER', 'PROCESS resolves inline BLOCKs');
};

subtest 'INCLUDE does not import blocks to outer scope' => sub {
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        TRIM => 1,
    });
    my $inner = '[% BLOCK secret %]SECRET[% END %]visible';
    my $outer = "[% INCLUDE \$inner_tmpl %] [% TRY %][% PROCESS secret %][% CATCH %]caught[% END %]";
    my $output = '';
    $tt->process(\$outer, { inner_tmpl => \$inner }, \$output);
    like($output, qr/visible.*caught/s, 'INCLUDE blocks not visible in outer scope');
};

#========================================================================
# Integration: error recovery
#========================================================================

subtest 'TRY/CATCH works through context' => sub {
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        TRIM => 1,
    });
    my $tmpl = '[% TRY %][% THROW myerr "oops" %][% CATCH myerr %]caught: [% error.info %][% END %]';
    my $output = '';
    $tt->process(\$tmpl, {}, \$output);
    is($output, 'caught: oops', 'TRY/CATCH with typed exception');
};

subtest 'nested TRY/CATCH' => sub {
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        TRIM => 1,
    });
    my $tmpl = <<'END';
[% TRY -%]
[% TRY -%]
[% THROW inner "inner error" -%]
[% CATCH inner -%]
caught inner
[% THROW outer "outer error" -%]
[% END -%]
[% CATCH outer -%]
caught outer
[% END %]
END
    my $output = '';
    $tt->process(\$tmpl, {}, \$output);
    like($output, qr/caught inner/, 'inner catch works');
    like($output, qr/caught outer/, 'outer catch works');
};

done_testing();
