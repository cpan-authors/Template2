#!/usr/bin/perl -w
#
# t/unit-document.t
#
# Unit tests for Template::Document — constructor (coderef & string blocks),
# accessors (block, blocks, variables, meta, AUTOLOAD), process (recursion
# detection, visit/leave, error propagation), class methods (as_perl,
# write_perl_file, catch_warnings).
#

use strict;
use lib qw( ./lib ../lib );
use Test::More;
use File::Temp qw( tempfile tempdir );

use Template::Document;
use Template::Constants qw( :error );

#========================================================================
# Mock context for process() tests
#========================================================================

package MockContext;

sub new {
    my ($class, %args) = @_;
    bless {
        RECURSION   => $args{RECURSION} || 0,
        visited     => [],
        left        => 0,
        catch_map   => {},
        throw_msg   => undef,
        throw_type  => undef,
    }, $class;
}

sub visit {
    my ($self, $doc, $blocks) = @_;
    push @{ $self->{visited} }, { doc => $doc, blocks => $blocks };
}

sub leave {
    my $self = shift;
    $self->{left}++;
}

sub throw {
    my ($self, $type, $info) = @_;
    $self->{throw_type} = $type;
    $self->{throw_msg}  = $info;
    require Template::Exception;
    die Template::Exception->new($type, $info);
}

sub catch {
    my ($self, $e) = @_;
    return $e;
}

package main;

#========================================================================
# Constructor tests
#========================================================================

# --- coderef BLOCK ---
{
    my $block = sub { return 'hello from block' };
    my $doc = Template::Document->new({
        BLOCK => $block,
    });
    ok($doc, 'new() with coderef BLOCK');
    isa_ok($doc, 'Template::Document');
    is(ref $doc->block(), 'CODE', 'block() returns coderef');
    is($doc->block()->(), 'hello from block', 'block sub returns expected text');
}

# --- string BLOCK (eval'd) ---
{
    my $doc = Template::Document->new({
        BLOCK => 'sub { return "compiled" }',
    });
    ok($doc, 'new() with string BLOCK');
    is(ref $doc->block(), 'CODE', 'string BLOCK eval into coderef');
    is($doc->block()->(), 'compiled', 'eval string block returns expected text');
}

# --- invalid string BLOCK ---
{
    my $doc = Template::Document->new({
        BLOCK => 'sub { this is invalid perl %%% }',
    });
    ok(!$doc, 'new() with invalid string BLOCK returns undef');
    like($Template::Document::ERROR, qr/./, 'error message set on compile failure');
}

# --- DEFBLOCKS as coderefs ---
{
    my $hdr = sub { 'header output' };
    my $ftr = sub { 'footer output' };
    my $doc = Template::Document->new({
        BLOCK     => sub { 'main' },
        DEFBLOCKS => { header => $hdr, footer => $ftr },
    });
    ok($doc, 'new() with DEFBLOCKS coderefs');
    my $blocks = $doc->blocks();
    is(ref $blocks, 'HASH', 'blocks() returns hashref');
    is($blocks->{header}->(), 'header output', 'DEFBLOCKS header sub works');
    is($blocks->{footer}->(), 'footer output', 'DEFBLOCKS footer sub works');
}

# --- DEFBLOCKS as strings ---
{
    my $doc = Template::Document->new({
        BLOCK     => sub { 'main' },
        DEFBLOCKS => {
            sidebar => 'sub { return "sidebar content" }',
        },
    });
    ok($doc, 'new() with DEFBLOCKS string');
    is(ref $doc->blocks()->{sidebar}, 'CODE', 'DEFBLOCKS string eval to coderef');
    is($doc->blocks()->{sidebar}->(), 'sidebar content', 'DEFBLOCKS string sub works');
}

# --- DEFBLOCKS with invalid string ---
{
    my $doc = Template::Document->new({
        BLOCK     => sub { 'main' },
        DEFBLOCKS => {
            broken => 'sub { invalid %%% }',
        },
    });
    ok(!$doc, 'new() with invalid DEFBLOCKS string returns undef');
}

# --- METADATA ---
{
    my $doc = Template::Document->new({
        BLOCK    => sub { 'main' },
        METADATA => {
            name    => 'mytemplate',
            author  => 'Test Author',
            version => '1.0',
        },
    });
    ok($doc, 'new() with METADATA');
    is($doc->{name},    'mytemplate',  'metadata name stored');
    is($doc->{author},  'Test Author', 'metadata author stored');
    is($doc->{version}, '1.0',        'metadata version stored');
}

# --- VARIABLES ---
{
    my $vars = { foo => 1, bar => 1 };
    my $doc = Template::Document->new({
        BLOCK     => sub { 'main' },
        VARIABLES => $vars,
    });
    ok($doc, 'new() with VARIABLES');
    is_deeply($doc->variables(), $vars, 'variables() returns VARIABLES hash');
}

# --- defaults (no DEFBLOCKS, no METADATA, no VARIABLES) ---
{
    my $doc = Template::Document->new({
        BLOCK => sub { 'bare minimum' },
    });
    ok($doc, 'new() with minimal args');
    is_deeply($doc->blocks(), {}, 'blocks() defaults to empty hashref');
    is($doc->variables(), undef, 'variables() is undef when not provided');
}

# --- _HOT starts at 0 ---
{
    my $doc = Template::Document->new({
        BLOCK => sub { 'test' },
    });
    is($doc->{_HOT}, 0, '_HOT initialized to 0');
}

#========================================================================
# block(), blocks(), variables() accessor tests
#========================================================================

{
    my $block = sub { 'accessor test' };
    my $defblocks = { nav => sub { 'nav' } };
    my $vars = { x => 1 };
    my $doc = Template::Document->new({
        BLOCK     => $block,
        DEFBLOCKS => $defblocks,
        VARIABLES => $vars,
    });

    is($doc->block(), $block, 'block() returns exact coderef');
    is($doc->blocks(), $defblocks, 'blocks() returns exact DEFBLOCKS ref');
    is($doc->variables(), $vars, 'variables() returns exact VARIABLES ref');
}

#========================================================================
# meta() tests
#========================================================================

{
    my $doc = Template::Document->new({
        BLOCK    => sub { 'meta test' },
        METADATA => {
            name    => 'test.tt',
            modtime => 1234567890,
            author  => 'Meta Author',
            title   => 'A Title',
        },
    });

    my $meta = $doc->meta();
    is(ref $meta, 'HASH', 'meta() returns hashref');
    is($meta->{author}, 'Meta Author', 'meta() includes author');
    is($meta->{title},  'A Title',     'meta() includes title');
    ok(!exists $meta->{name},    'meta() excludes name');
    ok(!exists $meta->{modtime}, 'meta() excludes modtime');
    ok(!exists $meta->{_BLOCK},  'meta() excludes _ prefixed keys');
    ok(!exists $meta->{_DEFBLOCKS}, 'meta() excludes _DEFBLOCKS');
    ok(!exists $meta->{_HOT},       'meta() excludes _HOT');
}

# --- meta with no custom metadata ---
{
    my $doc = Template::Document->new({
        BLOCK    => sub { 'no meta' },
        METADATA => { name => 'bare.tt' },
    });
    my $meta = $doc->meta();
    is_deeply($meta, {}, 'meta() empty when only name/modtime present');
}

#========================================================================
# AUTOLOAD tests
#========================================================================

{
    my $doc = Template::Document->new({
        BLOCK    => sub { 'autoload test' },
        METADATA => {
            title   => 'My Template',
            author  => 'Auto Load',
            version => '2.5',
        },
    });

    is($doc->title(),   'My Template', 'AUTOLOAD: title()');
    is($doc->author(),  'Auto Load',   'AUTOLOAD: author()');
    is($doc->version(), '2.5',         'AUTOLOAD: version()');
}

# --- AUTOLOAD for nonexistent metadata returns undef ---
{
    my $doc = Template::Document->new({
        BLOCK => sub { 'test' },
    });
    is($doc->nonexistent(), undef, 'AUTOLOAD: nonexistent key returns undef');
}

#========================================================================
# process() tests
#========================================================================

# --- basic process ---
{
    my $ctx = MockContext->new();
    my $doc = Template::Document->new({
        BLOCK     => sub { return 'processed output' },
        DEFBLOCKS => { aside => sub { 'aside' } },
    });

    my $output = $doc->process($ctx);
    is($output, 'processed output', 'process() returns block output');
    is(scalar @{ $ctx->{visited} }, 1, 'process() calls visit() once');
    is($ctx->{visited}[0]{doc}, $doc, 'visit() receives document ref');
    is($ctx->{left}, 1, 'process() calls leave() once');
}

# --- process passes context to block ---
{
    my $ctx = MockContext->new();
    my $received_ctx;
    my $doc = Template::Document->new({
        BLOCK => sub { $received_ctx = $_[0]; return 'ok' },
    });
    $doc->process($ctx);
    is($received_ctx, $ctx, 'process() passes context to block sub');
}

# --- _HOT flag during process ---
{
    my $ctx = MockContext->new();
    my $hot_during;
    my $doc = Template::Document->new({
        BLOCK => sub {
            my $self_ref = $_[0];  # context, not doc
            return 'hot check';
        },
    });

    is($doc->{_HOT}, 0, '_HOT is 0 before process');
    $doc->process($ctx);
    is($doc->{_HOT}, 0, '_HOT is 0 after process completes');
}

# --- recursion detection ---
{
    my $ctx = MockContext->new();
    my $doc = Template::Document->new({
        BLOCK    => sub { return 'should not reach' },
        METADATA => { name => 'recursive.tt' },
    });

    $doc->{_HOT} = 1;  # simulate already processing
    eval { $doc->process($ctx) };
    ok($@, 'process() throws on recursion when _HOT and !RECURSION');
    like($ctx->{throw_msg}, qr/recursion.*recursive\.tt/,
        'recursion error mentions template name');
    is($ctx->{throw_type}, Template::Constants::ERROR_FILE,
        'recursion error type is ERROR_FILE');
}

# --- recursion allowed with RECURSION flag ---
{
    my $ctx = MockContext->new(RECURSION => 1);
    my $doc = Template::Document->new({
        BLOCK    => sub { return 're-entered' },
        METADATA => { name => 'recursive.tt' },
    });

    $doc->{_HOT} = 1;
    my $output = $doc->process($ctx);
    is($output, 're-entered', 'process() allows recursion when RECURSION is set');
}

# --- process resets _HOT on block error ---
{
    my $ctx = MockContext->new();
    my $doc = Template::Document->new({
        BLOCK => sub { die "block error\n" },
    });

    eval { $doc->process($ctx) };
    ok($@, 'process() propagates block error');
    is($doc->{_HOT}, 0, '_HOT reset to 0 even after block error');
    is($ctx->{left}, 1, 'leave() still called on error');
}

# --- process with defblocks passed to visit ---
{
    my $ctx = MockContext->new();
    my $defblocks = {
        header => sub { 'hdr' },
        footer => sub { 'ftr' },
    };
    my $doc = Template::Document->new({
        BLOCK     => sub { 'main' },
        DEFBLOCKS => $defblocks,
    });

    $doc->process($ctx);
    is_deeply(
        $ctx->{visited}[0]{blocks},
        $defblocks,
        'process() passes DEFBLOCKS to visit()'
    );
}

#========================================================================
# as_perl() class method tests
#========================================================================

{
    my $perl = Template::Document->as_perl({
        BLOCK     => 'sub { return "hello" }',
        DEFBLOCKS => {},
        METADATA  => { name => 'test.tt' },
    });

    ok($perl, 'as_perl() returns content');
    like($perl, qr/Template::Document->new/,
        'as_perl() includes constructor call');
    like($perl, qr/METADATA/, 'as_perl() includes METADATA section');
    like($perl, qr/BLOCK/,    'as_perl() includes BLOCK section');
    like($perl, qr/DEFBLOCKS/, 'as_perl() includes DEFBLOCKS section');
    like($perl, qr/'name' => 'test\.tt'/, 'as_perl() includes metadata values');
}

# --- as_perl with defblocks ---
{
    my $perl = Template::Document->as_perl({
        BLOCK     => 'sub { return "main" }',
        DEFBLOCKS => {
            header => 'sub { return "hdr" }',
        },
        METADATA => {},
    });

    like($perl, qr/'header' => sub/, 'as_perl() includes defblock entries');
}

# --- as_perl escapes metadata values ---
{
    my $perl = Template::Document->as_perl({
        BLOCK     => 'sub { 1 }',
        DEFBLOCKS => {},
        METADATA  => { note => "it's a \"test\\" },
    });

    like($perl, qr/it\\'s a "test\\\\/, 'as_perl() escapes quotes and backslashes in metadata');
}

# --- as_perl output is eval-able ---
{
    my $perl = Template::Document->as_perl({
        BLOCK     => 'sub { return "roundtrip" }',
        DEFBLOCKS => {
            sidebar => 'sub { return "side" }',
        },
        METADATA  => { name => 'roundtrip.tt', author => 'Test' },
    });

    my $doc = eval $perl;
    ok(!$@, 'as_perl() output evaluates without error') or diag $@;
    ok($doc, 'as_perl() output creates Document object');
    isa_ok($doc, 'Template::Document');
    is($doc->block()->(), 'roundtrip', 'roundtrip: main block works');
    is($doc->blocks()->{sidebar}->(), 'side', 'roundtrip: defblock works');
    is($doc->name(), 'roundtrip.tt', 'roundtrip: metadata accessible');
    is($doc->author(), 'Test', 'roundtrip: metadata author');
}

# --- as_perl version stamp ---
{
    my $perl = Template::Document->as_perl({
        BLOCK     => 'sub { 1 }',
        DEFBLOCKS => {},
        METADATA  => {},
    });
    like($perl, qr/Template Toolkit version/,
        'as_perl() includes version comment header');
}

#========================================================================
# write_perl_file() tests
#========================================================================

{
    my $dir = tempdir(CLEANUP => 1);
    my $file = "$dir/compiled.pl";

    my $ok = Template::Document->write_perl_file($file, {
        BLOCK     => 'sub { return "from file" }',
        DEFBLOCKS => {},
        METADATA  => { name => 'file.tt' },
    });

    ok($ok, 'write_perl_file() returns true on success');
    ok(-f $file, 'write_perl_file() creates the file');

    my $doc = do $file;
    ok($doc, 'compiled file loads with do') or diag $@;
    isa_ok($doc, 'Template::Document');
    is($doc->block()->(), 'from file', 'loaded Document block works');
    is($doc->name(), 'file.tt', 'loaded Document metadata accessible');
}

# --- write_perl_file with undef filename ---
{
    my $ok = Template::Document->write_perl_file(undef, {
        BLOCK     => 'sub { 1 }',
        DEFBLOCKS => {},
        METADATA  => {},
    });
    ok(!$ok, 'write_perl_file() with undef filename returns undef');
    like($Template::Document::ERROR, qr/invalid filename/,
        'error message for undef filename');
}

# --- write_perl_file with empty filename ---
{
    my $ok = Template::Document->write_perl_file('', {
        BLOCK     => 'sub { 1 }',
        DEFBLOCKS => {},
        METADATA  => {},
    });
    ok(!$ok, 'write_perl_file() with empty filename returns undef');
    like($Template::Document::ERROR, qr/invalid filename/,
        'error message for empty filename');
}

# --- write_perl_file with defblocks ---
{
    my $dir = tempdir(CLEANUP => 1);
    my $file = "$dir/with_blocks.pl";

    Template::Document->write_perl_file($file, {
        BLOCK     => 'sub { return "main" }',
        DEFBLOCKS => {
            nav => 'sub { return "navigation" }',
        },
        METADATA  => { name => 'blocks.tt' },
    });

    my $doc = do $file;
    ok($doc, 'loaded document with defblocks');
    is($doc->blocks()->{nav}->(), 'navigation', 'loaded defblock works');
}

# --- write_perl_file with UTF-8 content ---
{
    my $dir = tempdir(CLEANUP => 1);
    my $file = "$dir/utf8.pl";

    my $utf8_str = "sub { return \"caf\x{e9}\" }";
    utf8::upgrade($utf8_str);

    Template::Document->write_perl_file($file, {
        BLOCK     => $utf8_str,
        DEFBLOCKS => {},
        METADATA  => { name => 'utf8.tt' },
    });

    ok(-f $file, 'write_perl_file creates file for UTF-8 content');

    open my $fh, '<:raw', $file or die "Cannot open $file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    like($content, qr/^use utf8;/m, 'UTF-8 file has use utf8 pragma');
}

#========================================================================
# catch_warnings() tests
#========================================================================

{
    local $Template::Document::COMPERR = '';
    Template::Document::catch_warnings('warning one');
    is($Template::Document::COMPERR, 'warning one',
        'catch_warnings accumulates first warning');

    Template::Document::catch_warnings('warning two');
    is($Template::Document::COMPERR, 'warning onewarning two',
        'catch_warnings accumulates multiple warnings');
}

#========================================================================
# inheritance from Template::Base
#========================================================================

{
    isa_ok('Template::Document', 'Template::Base');

    my $err = Template::Document->error('test error');
    is(Template::Document->error(), 'test error',
        'error() class method works via Base');
}

#========================================================================
# mixed DEFBLOCKS (some coderefs, some strings)
#========================================================================

{
    my $doc = Template::Document->new({
        BLOCK     => sub { 'main' },
        DEFBLOCKS => {
            code_block   => sub { 'from code' },
            string_block => 'sub { return "from string" }',
        },
    });

    ok($doc, 'new() with mixed DEFBLOCKS');
    is($doc->blocks()->{code_block}->(),   'from code',   'mixed: coderef block works');
    is($doc->blocks()->{string_block}->(), 'from string', 'mixed: string block works');
}

#========================================================================
# process() interaction with multiple documents
#========================================================================

{
    my $ctx = MockContext->new();
    my $doc1 = Template::Document->new({
        BLOCK    => sub { 'doc1' },
        METADATA => { name => 'first.tt' },
    });
    my $doc2 = Template::Document->new({
        BLOCK    => sub { 'doc2' },
        METADATA => { name => 'second.tt' },
    });

    $doc1->process($ctx);
    $doc2->process($ctx);

    is(scalar @{ $ctx->{visited} }, 2, 'two visits for two documents');
    is($ctx->{left}, 2, 'two leaves for two documents');
}

#========================================================================
# edge case: block returns empty string
#========================================================================

{
    my $ctx = MockContext->new();
    my $doc = Template::Document->new({
        BLOCK => sub { '' },
    });
    my $output = $doc->process($ctx);
    is($output, '', 'process() handles empty string return');
}

# --- block returns undef ---
{
    my $ctx = MockContext->new();
    my $doc = Template::Document->new({
        BLOCK => sub { undef },
    });
    my $output = $doc->process($ctx);
    is($output, undef, 'process() handles undef return');
}

#========================================================================
# as_perl with multiple metadata items
#========================================================================

{
    my $perl = Template::Document->as_perl({
        BLOCK     => 'sub { 1 }',
        DEFBLOCKS => {},
        METADATA  => {
            name    => 'multi.tt',
            modtime => '1234567890',
            author  => 'Someone',
        },
    });

    like($perl, qr/'name' => 'multi\.tt'/,     'as_perl: name metadata');
    like($perl, qr/'modtime' => '1234567890'/, 'as_perl: modtime metadata');
    like($perl, qr/'author' => 'Someone'/,     'as_perl: author metadata');
}

#========================================================================
# $DEBUG variable
#========================================================================

{
    is($Template::Document::DEBUG, 0, '$DEBUG defaults to 0');
}

#========================================================================
# new() with string BLOCK that produces warnings
#========================================================================

{
    local $Template::Document::COMPERR = '';
    my $doc = Template::Document->new({
        BLOCK => 'do { warn "test warning during compile"; sub { "warned" } }',
    });
    ok($doc, 'new() succeeds despite compile warnings');
    like($Template::Document::COMPERR, qr/test warning during compile/,
        'compile warning captured in $COMPERR');
    is($doc->block()->(), 'warned', 'block still works after warning');
}

done_testing();
