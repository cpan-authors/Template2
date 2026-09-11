#============================================================= -*-perl-*-
#
# t/unit-filters.t
#
# Unit tests for Template::Filters — constructor, fetch/store methods,
# every static filter, every dynamic filter factory, helper functions,
# RFC toggling, and TOLERANT/DEBUG modes.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );
use Test::More;
use Template::Filters;
use Template::Constants qw( :status :debug );

#------------------------------------------------------------------------
# Minimal mock context for dynamic filters that need one
#------------------------------------------------------------------------
{
    package MockContext;
    sub new {
        my ($class, %args) = @_;
        bless \%args, $class;
    }
    sub stash      { $_[0]->{stash}     // MockStash->new() }
    sub eval_perl  { $_[0]->{eval_perl} // 0 }
    sub config     { $_[0]->{config}    // {} }
    sub process    { my ($self, $ref) = @_; return $$ref }
    sub throw      { die Template::Exception->new(@_[1,2]) }
}

{
    package MockStash;
    sub new { bless {}, shift }
}

# We need Template::Exception for some factory error returns
use Template::Exception;


#========================================================================
# Constructor / _init
#========================================================================

subtest 'constructor — defaults' => sub {
    my $f = Template::Filters->new({});
    isa_ok($f, 'Template::Filters');
    is(ref $f->{FILTERS}, 'HASH', 'FILTERS is a hashref');
    is(scalar keys %{$f->{FILTERS}}, 0, 'no custom filters by default');
    is($f->{TOLERANT}, 0, 'TOLERANT defaults to 0');
    is($f->{DEBUG}, 0, 'DEBUG defaults to 0');
};

subtest 'constructor — custom FILTERS' => sub {
    my $custom = { 'myfilter' => sub { "custom:$_[0]" } };
    my $f = Template::Filters->new({ FILTERS => $custom });
    ok(exists $f->{FILTERS}{myfilter}, 'custom filter registered');
    is($f->{FILTERS}{myfilter}->('test'), 'custom:test', 'custom filter works');
};

subtest 'constructor — TOLERANT flag' => sub {
    my $f = Template::Filters->new({ TOLERANT => 1 });
    is($f->{TOLERANT}, 1, 'TOLERANT flag stored');
};

subtest 'constructor — DEBUG flag' => sub {
    my $f = Template::Filters->new({ DEBUG => DEBUG_FILTERS });
    ok($f->{DEBUG} & DEBUG_FILTERS, 'DEBUG_FILTERS bit set');

    my $f2 = Template::Filters->new({ DEBUG => DEBUG_PLUGINS });
    is($f2->{DEBUG} & DEBUG_FILTERS, 0, 'unrelated debug bits filtered out');
};


#========================================================================
# store() method
#========================================================================

subtest 'store — static filter' => sub {
    my $f = Template::Filters->new({});
    my $result = $f->store('myfilt', sub { uc $_[0] });
    is($result, 1, 'store returns 1');
    is($f->{FILTERS}{myfilt}->('hello'), 'HELLO', 'stored filter works');
};

subtest 'store — dynamic filter' => sub {
    my $f = Template::Filters->new({});
    $f->store('dynfilt', [ sub { my ($ctx, $n) = @_; return sub { $_[0] x $n } }, 1 ]);
    is(ref $f->{FILTERS}{dynfilt}, 'ARRAY', 'dynamic filter stored as arrayref');
};


#========================================================================
# fetch() method
#========================================================================

subtest 'fetch — static filter by name' => sub {
    my $f = Template::Filters->new({});
    my $filter = $f->fetch('html', undef, undef);
    is(ref $filter, 'CODE', 'html filter is a coderef');
    is($filter->('<b>'), '&lt;b&gt;', 'html filter works');
};

subtest 'fetch — coderef passed directly' => sub {
    my $f = Template::Filters->new({});
    my $code = sub { "wrapped:$_[0]" };
    my $result = $f->fetch($code, undef, undef);
    is($result, $code, 'coderef returned as-is');
};

subtest 'fetch — unknown filter declined' => sub {
    my $f = Template::Filters->new({});
    my ($filter, $status) = $f->fetch('nonexistent_xyzzy', undef, undef);
    is($filter, undef, 'filter is undef');
    is($status, STATUS_DECLINED, 'returns STATUS_DECLINED');
};

subtest 'fetch — custom filter overrides global' => sub {
    my $f = Template::Filters->new({
        FILTERS => { 'html' => sub { "custom_html:$_[0]" } }
    });
    my $filter = $f->fetch('html', undef, undef);
    is($filter->('<b>'), 'custom_html:<b>', 'custom html filter used');
};

subtest 'fetch — dynamic filter with args' => sub {
    my $f = Template::Filters->new({});
    my $ctx = MockContext->new();
    my $filter = $f->fetch('indent', [8], $ctx);
    is(ref $filter, 'CODE', 'indent filter is a coderef');
    like($filter->('hello'), qr/^\s{8}hello$/, 'indent filter applied with arg');
};

subtest 'fetch — TOLERANT downgrades errors' => sub {
    my $f = Template::Filters->new({
        TOLERANT => 1,
        FILTERS  => { 'badfilt' => [ 'not_a_coderef', 1 ] },
    });
    my ($filter, $status) = $f->fetch('badfilt', undef, undef);
    is($filter, undef, 'filter is undef');
    is($status, STATUS_DECLINED, 'error downgraded to DECLINED');
};

subtest 'fetch — non-TOLERANT returns error' => sub {
    my $f = Template::Filters->new({
        FILTERS => { 'badfilt' => [ 'not_a_coderef', 1 ] },
    });
    my ($error, $status) = $f->fetch('badfilt', undef, undef);
    like($error, qr/invalid FILTER/, 'error message returned');
    is($status, STATUS_ERROR, 'returns STATUS_ERROR');
};

subtest 'fetch — invalid non-dynamic factory' => sub {
    my $f = Template::Filters->new({
        FILTERS => { 'badfilt' => 'just_a_string' },
    });
    my ($error, $status) = $f->fetch('badfilt', undef, undef);
    like($error, qr/invalid FILTER entry.*not a CODE ref/, 'error for non-code filter');
    is($status, STATUS_ERROR, 'STATUS_ERROR returned');
};

subtest 'fetch — dynamic factory returning non-coderef' => sub {
    my $f = Template::Filters->new({
        FILTERS => { 'badfact' => [ sub { return 'not_code' }, 1 ] },
    });
    my ($error, $status) = $f->fetch('badfact', undef, undef);
    like($error, qr/invalid FILTER.*not a CODE ref/, 'error for non-code dynamic result');
    is($status, STATUS_ERROR, 'STATUS_ERROR returned');
};

subtest 'fetch — dynamic factory that dies' => sub {
    my $f = Template::Filters->new({
        FILTERS => { 'diefilt' => [ sub { die "factory boom\n" }, 1 ] },
    });
    my ($error, $status) = $f->fetch('diefilt', undef, undef);
    like($error, qr/factory boom/, 'caught die from factory');
    is($status, STATUS_ERROR, 'STATUS_ERROR returned');
};


#========================================================================
# Static filter functions — called directly
#========================================================================

subtest 'html_filter' => sub {
    is(Template::Filters::html_filter(''), '', 'empty string');
    is(Template::Filters::html_filter('hello'), 'hello', 'no special chars');
    is(Template::Filters::html_filter('&'), '&amp;', 'ampersand');
    is(Template::Filters::html_filter('<'), '&lt;', 'less than');
    is(Template::Filters::html_filter('>'), '&gt;', 'greater than');
    is(Template::Filters::html_filter('"'), '&quot;', 'double quote');
    is(Template::Filters::html_filter("'"), '&#39;', 'single quote');
    is(
        Template::Filters::html_filter('<script>alert("xss")</script>'),
        '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;',
        'full XSS example'
    );
    is(
        Template::Filters::html_filter('a & b < c > d " e \' f'),
        'a &amp; b &lt; c &gt; d &quot; e &#39; f',
        'all five chars in one string'
    );
};

subtest 'xml_filter' => sub {
    is(Template::Filters::xml_filter(''), '', 'empty string');
    is(Template::Filters::xml_filter('&'), '&amp;', 'ampersand');
    is(Template::Filters::xml_filter('<'), '&lt;', 'less than');
    is(Template::Filters::xml_filter('>'), '&gt;', 'greater than');
    is(Template::Filters::xml_filter('"'), '&quot;', 'double quote');
    is(Template::Filters::xml_filter("'"), '&apos;', 'single quote uses &apos;');
};

subtest 'html_paragraph' => sub {
    is(
        Template::Filters::html_paragraph('hello'),
        "<p>\nhello</p>\n",
        'single paragraph'
    );
    is(
        Template::Filters::html_paragraph("para1\n\npara2"),
        "<p>\npara1\n</p>\n\n<p>\npara2</p>\n",
        'two paragraphs'
    );
    is(
        Template::Filters::html_paragraph("a\n\n\n\nb"),
        "<p>\na\n</p>\n\n<p>\nb</p>\n",
        'multiple blank lines still one split'
    );
    is(
        Template::Filters::html_paragraph("a\r\n\r\nb"),
        "<p>\na\n</p>\n\n<p>\nb</p>\n",
        'CRLF paragraph breaks'
    );
};

subtest 'html_para_break' => sub {
    is(
        Template::Filters::html_para_break("a\n\nb"),
        "a\n<br />\n<br />\nb",
        'double newline replaced with br tags'
    );
    is(
        Template::Filters::html_para_break("single\nline"),
        "single\nline",
        'single newline untouched'
    );
};

subtest 'html_line_break' => sub {
    is(
        Template::Filters::html_line_break("a\nb\nc"),
        "a<br />\nb<br />\nc",
        'newlines get br tags'
    );
    is(
        Template::Filters::html_line_break("no newlines"),
        "no newlines",
        'no newlines untouched'
    );
    is(
        Template::Filters::html_line_break("crlf\r\nhere"),
        "crlf<br />\r\nhere",
        'CRLF gets br tag'
    );
};

subtest 'uri_filter — RFC3986 default' => sub {
    Template::Filters::use_rfc3986();
    is(Template::Filters::uri_filter('hello'), 'hello', 'safe chars unchanged');
    is(Template::Filters::uri_filter('hello world'), 'hello%20world', 'space encoded');
    is(Template::Filters::uri_filter('a&b=c'), 'a%26b%3Dc', 'query chars encoded');
    is(Template::Filters::uri_filter('/path/to'), '%2Fpath%2Fto', 'slashes encoded');
    is(Template::Filters::uri_filter(''), '', 'empty string');
};

subtest 'url_filter — preserves URL chars' => sub {
    Template::Filters::use_rfc3986();
    is(Template::Filters::url_filter('http://example.com/path'), 'http://example.com/path', 'URL chars preserved');
    is(Template::Filters::url_filter('hello world'), 'hello%20world', 'space still encoded');
    is(Template::Filters::url_filter('a=1&b=2'), 'a=1&b=2', 'query delimiters preserved');
};

subtest 'RFC toggle — use_rfc2732 / use_rfc3986' => sub {
    Template::Filters::use_rfc2732();
    is(Template::Filters::uri_filter("it's"), "it's", "RFC2732: apostrophe is safe");
    is(Template::Filters::uri_filter('a!b'), 'a!b', 'RFC2732: exclamation is safe');

    Template::Filters::use_rfc3986();
    is(Template::Filters::uri_filter("it's"), "it%27s", "RFC3986: apostrophe encoded");
    is(Template::Filters::uri_filter('a!b'), 'a%21b', 'RFC3986: exclamation encoded');
};

subtest 'uri_filter — UTF-8' => sub {
    Template::Filters::use_rfc3986();
    my $wide = "\x{65e5}\x{672c}";
    my $encoded = Template::Filters::uri_filter($wide);
    like($encoded, qr/^%[0-9A-F]{2}/, 'wide chars produce percent-encoded bytes');
    unlike($encoded, qr/[^\x00-\x7f]/, 'no raw high bytes in output');
};

subtest 'static inline filters' => sub {
    my $f = Template::Filters->new({});

    my $upper = $f->fetch('upper', undef, undef);
    is($upper->('hello'), 'HELLO', 'upper filter');

    my $lower = $f->fetch('lower', undef, undef);
    is($lower->('HELLO'), 'hello', 'lower filter');

    my $ucf = $f->fetch('ucfirst', undef, undef);
    is($ucf->('hello'), 'Hello', 'ucfirst filter');

    my $lcf = $f->fetch('lcfirst', undef, undef);
    is($lcf->('HELLO'), 'hELLO', 'lcfirst filter');

    my $null = $f->fetch('null', undef, undef);
    is($null->('anything'), '', 'null filter returns empty');

    my $trim = $f->fetch('trim', undef, undef);
    my $t1 = '  hello  ';
    is($trim->($t1), 'hello', 'trim strips both sides');
    my $t2 = 'hello';
    is($trim->($t2), 'hello', 'trim on clean string');
    my $t3 = "  \t mixed \n ";
    is($trim->($t3), "mixed", 'trim strips tabs and newlines');

    my $collapse = $f->fetch('collapse', undef, undef);
    my $c1 = '  hello   world  ';
    is($collapse->($c1), 'hello world', 'collapse normalizes whitespace');
    my $c2 = "a\n\tb";
    is($collapse->($c2), 'a b', 'collapse handles tabs and newlines');
};

subtest 'stderr filter' => sub {
    my $f = Template::Filters->new({});
    my $stderr_filter = $f->fetch('stderr', undef, undef);

    my $captured = '';
    {
        local *STDERR;
        open STDERR, '>', \$captured or die "Cannot redirect STDERR: $!";
        my $result = $stderr_filter->('test message');
        is($result, '', 'stderr filter returns empty');
    }
    is($captured, 'test message', 'stderr filter printed to STDERR');
};


#========================================================================
# Dynamic filter factories
#========================================================================

subtest 'indent_filter_factory' => sub {
    my $ctx = MockContext->new();

    my ($filter) = Template::Filters::indent_filter_factory($ctx);
    is($filter->('hello'), '    hello', 'default indent is 4 spaces');
    is($filter->("a\nb"), "    a\n    b", 'indents each line');

    my ($f8) = Template::Filters::indent_filter_factory($ctx, 8);
    is($f8->('hi'), '        hi', 'numeric indent of 8');

    my ($ftab) = Template::Filters::indent_filter_factory($ctx, "\t");
    is($ftab->('hi'), "\thi", 'string indent with tab');

    my ($f0) = Template::Filters::indent_filter_factory($ctx, 0);
    is($f0->('hi'), 'hi', 'zero indent');

    my ($fdef) = Template::Filters::indent_filter_factory($ctx, undef);
    is($fdef->('x'), '    x', 'undef defaults to 4 spaces');

    my ($fempty) = Template::Filters::indent_filter_factory($ctx);
    is($fempty->(undef), '    ', 'undef text becomes padded empty');
};

subtest 'format_filter_factory' => sub {
    my $ctx = MockContext->new();

    my ($filter) = Template::Filters::format_filter_factory($ctx);
    is($filter->('hello'), 'hello', 'default format is %s');

    my ($fpct) = Template::Filters::format_filter_factory($ctx, '(%s)');
    is($fpct->('hello'), '(hello)', 'custom format wraps');

    my ($fnum) = Template::Filters::format_filter_factory($ctx, '%05d');
    is($fnum->('42'), '00042', 'numeric format');

    my ($fml) = Template::Filters::format_filter_factory($ctx, '> %s');
    is($fml->("a\nb\nc"), "> a\n> b\n> c", 'multi-line format');

    my ($fdef) = Template::Filters::format_filter_factory($ctx, undef);
    is($fdef->('test'), 'test', 'undef format defaults to %s');
};

subtest 'truncate_filter_factory' => sub {
    my $ctx = MockContext->new();

    my ($filter) = Template::Filters::truncate_filter_factory($ctx);
    my $short = 'hello';
    is($filter->($short), $short, 'short text unchanged');

    my $long = 'a' x 50;
    my $result = $filter->($long);
    is(length($result), $Template::Filters::TRUNCATE_LENGTH, 'truncated to default length');
    like($result, qr/\.\.\.$/, 'ends with default addon');

    my ($f10) = Template::Filters::truncate_filter_factory($ctx, 10);
    is($f10->('short'), 'short', 'short text not truncated');
    is($f10->('this is a long text'), 'this is...', 'truncated to 10 with addon');

    my ($f10x) = Template::Filters::truncate_filter_factory($ctx, 10, '!');
    is($f10x->('this is a long text'), 'this is a!', 'custom addon char');

    my ($f3) = Template::Filters::truncate_filter_factory($ctx, 3);
    is($f3->('abcdef'), '...', 'very short truncation = just addon');
};

subtest 'truncate — HTML entity awareness' => sub {
    my $ctx = MockContext->new();

    my ($f10) = Template::Filters::truncate_filter_factory($ctx, 10);
    my $entity_text = 'abc&amp;defghij';
    my $result = $f10->($entity_text);
    ok(length($result) <= 30, 'result not too long');
    unlike($result, qr/&amp$/, 'entity not split mid-reference');

    my ($f5) = Template::Filters::truncate_filter_factory($ctx, 5, '');
    is($f5->('ab&lt;de'), 'ab&lt;de', 'entity text within limit');

    my ($f5h) = Template::Filters::truncate_filter_factory($ctx, 5, '&hellip;');
    my $r = $f5h->('abcdefghij');
    is($r, 'abcd&hellip;', 'HTML entity addon counts as 1 char');
};

subtest 'repeat_filter_factory' => sub {
    my $ctx = MockContext->new();

    my ($filter) = Template::Filters::repeat_filter_factory($ctx);
    is($filter->('ha'), 'ha', 'default repeat is 1');

    my ($f3) = Template::Filters::repeat_filter_factory($ctx, 3);
    is($f3->('ha'), 'hahaha', 'repeat 3 times');

    my ($f0) = Template::Filters::repeat_filter_factory($ctx, 0);
    is($f0->('anything'), '', 'repeat 0 returns empty');

    my ($fundef) = Template::Filters::repeat_filter_factory($ctx, undef);
    is($fundef->('x'), 'x', 'undef defaults to 1');
};

subtest 'replace_filter_factory' => sub {
    my $ctx = MockContext->new();

    my ($filter) = Template::Filters::replace_filter_factory($ctx, 'foo', 'bar');
    is($filter->('foo baz foo'), 'bar baz bar', 'simple replace');

    my ($fregex) = Template::Filters::replace_filter_factory($ctx, '\d+', '#');
    is($fregex->('abc 123 def 456'), 'abc # def #', 'regex replace');

    my ($fnone) = Template::Filters::replace_filter_factory($ctx, 'xyz', 'abc');
    is($fnone->('hello'), 'hello', 'no match leaves text unchanged');

    my ($fdef) = Template::Filters::replace_filter_factory($ctx);
    is($fdef->('hello'), 'hello', 'default args produce no change');
};

subtest 'remove_filter_factory' => sub {
    my $ctx = MockContext->new();

    my ($filter) = Template::Filters::remove_filter_factory($ctx, 'foo');
    is($filter->('foo bar foo'), ' bar ', 'removes all occurrences');

    my ($fregex) = Template::Filters::remove_filter_factory($ctx, '\s+');
    is($fregex->('a b c'), 'abc', 'regex remove');

    my ($fundef) = Template::Filters::remove_filter_factory($ctx);
    is(ref $fundef, 'CODE', 'undef search returns a filter');
};

subtest 'eval_filter_factory' => sub {
    my $ctx = MockContext->new();
    my ($filter) = Template::Filters::eval_filter_factory($ctx);
    is(ref $filter, 'CODE', 'eval filter is a coderef');
    is($filter->('hello [% 1 + 1 %]'), 'hello [% 1 + 1 %]', 'mock context returns text as-is');
};

subtest 'perl_filter_factory — EVAL_PERL disabled' => sub {
    my $ctx = MockContext->new(eval_perl => 0);
    my ($filter, $error) = Template::Filters::perl_filter_factory($ctx);
    is($filter, undef, 'filter is undef when EVAL_PERL off');
    isa_ok($error, 'Template::Exception');
    is($error->type(), 'perl', 'exception type is perl');
    like($error->info(), qr/EVAL_PERL is not set/, 'error message');
};

subtest 'perl_filter_factory — EVAL_PERL enabled' => sub {
    my $ctx = MockContext->new(eval_perl => 1);
    my ($filter) = Template::Filters::perl_filter_factory($ctx);
    is(ref $filter, 'CODE', 'filter returned when EVAL_PERL on');
    is($filter->('"hello"'), 'hello', 'perl eval works');
};

subtest 'redirect_filter_factory — no OUTPUT_PATH' => sub {
    my $ctx = MockContext->new(config => {});
    my ($filter, $error) = Template::Filters::redirect_filter_factory($ctx, 'test.txt');
    is($filter, undef, 'filter is undef without OUTPUT_PATH');
    isa_ok($error, 'Template::Exception');
    like($error->info(), qr/OUTPUT_PATH/, 'mentions OUTPUT_PATH');
};

subtest 'redirect_filter_factory — directory traversal blocked' => sub {
    my $ctx = MockContext->new(config => { OUTPUT_PATH => '/tmp/tt_test' });
    eval { Template::Filters::redirect_filter_factory($ctx, '../etc/passwd') };
    ok($@, 'directory traversal throws');
    like("$@", qr/relative filenames/, 'error mentions relative filenames');
};

subtest 'redirect_filter_factory — valid path' => sub {
    my $ctx = MockContext->new(config => { OUTPUT_PATH => '/tmp/tt_test_filters' });
    my ($filter) = Template::Filters::redirect_filter_factory($ctx, 'output.txt');
    is(ref $filter, 'CODE', 'filter returned with valid OUTPUT_PATH');
};

subtest 'stdout_filter_factory' => sub {
    my $ctx = MockContext->new();
    my ($filter) = Template::Filters::stdout_filter_factory($ctx);
    is(ref $filter, 'CODE', 'stdout filter is a coderef');

    my $captured = '';
    {
        local *STDOUT;
        open STDOUT, '>', \$captured or die "Cannot redirect STDOUT: $!";
        my $result = $filter->('test output');
        is($result, '', 'stdout filter returns empty');
    }
    is($captured, 'test output', 'stdout filter printed to STDOUT');
};

subtest 'html_entity_filter_factory' => sub {
    my $ctx = MockContext->new();
    my ($filter_or_undef, $error) = Template::Filters::html_entity_filter_factory($ctx);
    if (eval { require HTML::Entities; 1 }) {
        is(ref $filter_or_undef, 'CODE', 'HTML::Entities available — filter returned');
        like($filter_or_undef->('<&>'), qr/&lt;/, 'entity encoding works');
    }
    else {
        is($filter_or_undef, undef, 'no HTML::Entities — filter is undef');
        isa_ok($error, 'Template::Exception', 'exception returned');
    }
};


#========================================================================
# Helper functions
#========================================================================

subtest '_visual_length' => sub {
    is(Template::Filters::_visual_length('hello'), 5, 'plain text');
    is(Template::Filters::_visual_length('a&amp;b'), 3, 'named entity counts as 1');
    is(Template::Filters::_visual_length('&#123;'), 1, 'numeric entity counts as 1');
    is(Template::Filters::_visual_length('&#x1F600;'), 1, 'hex entity counts as 1');
    is(Template::Filters::_visual_length('&lt;&gt;'), 2, 'two entities = length 2');
    is(Template::Filters::_visual_length(''), 0, 'empty string');
    is(Template::Filters::_visual_length('no&entities'), 11, 'bare ampersand not treated as entity');
};

subtest '_truncate_visual' => sub {
    is(Template::Filters::_truncate_visual('hello', 3), 'hel', 'plain truncation');
    is(Template::Filters::_truncate_visual('a&amp;b', 2), 'a&amp;', 'entity preserved as unit');
    is(Template::Filters::_truncate_visual('a&amp;b', 3), 'a&amp;b', 'exact length');
    is(Template::Filters::_truncate_visual('a&amp;b', 10), 'a&amp;b', 'over-length returns all');
    is(Template::Filters::_truncate_visual('', 5), '', 'empty string');
    is(Template::Filters::_truncate_visual('abc', 0), '', 'zero maxlen');
};

subtest 'uri_escapes' => sub {
    my $escapes = Template::Filters::uri_escapes();
    is(ref $escapes, 'HASH', 'returns a hashref');
    is($escapes->{' '}, '%20', 'space encoded');
    is($escapes->{'A'}, '%41', 'A encoded (table has all 256)');
    is(scalar keys %$escapes, 256, '256 entries (all bytes)');
};


#========================================================================
# Package variable defaults
#========================================================================

subtest 'package variable defaults' => sub {
    is($Template::Filters::TRUNCATE_LENGTH, 32, 'default truncate length');
    is($Template::Filters::TRUNCATE_ADDON, '...', 'default truncate addon');
    is(ref $Template::Filters::UNSAFE_SPEC, 'HASH', 'UNSAFE_SPEC is hash');
    ok(exists $Template::Filters::UNSAFE_SPEC->{RFC2732}, 'RFC2732 spec exists');
    ok(exists $Template::Filters::UNSAFE_SPEC->{RFC3986}, 'RFC3986 spec exists');
};

subtest '$FILTERS registry completeness' => sub {
    my @expected_static = qw(
        html html_para html_break html_para_break html_line_break
        xml uri url upper lower ucfirst lcfirst stderr trim null collapse
    );
    my @expected_dynamic = qw(
        html_entity indent format truncate repeat replace remove
        eval evaltt perl evalperl redirect file stdout
    );

    for my $name (@expected_static) {
        ok(exists $Template::Filters::FILTERS->{$name}, "static filter '$name' registered");
        is(ref $Template::Filters::FILTERS->{$name}, 'CODE', "'$name' is a coderef")
            unless $name eq 'html_entity';
    }

    for my $name (@expected_dynamic) {
        ok(exists $Template::Filters::FILTERS->{$name}, "dynamic filter '$name' registered");
        is(ref $Template::Filters::FILTERS->{$name}, 'ARRAY', "'$name' is an arrayref");
        is($Template::Filters::FILTERS->{$name}[1], 1, "'$name' has dynamic flag set");
    }
};


#========================================================================
# Aliases
#========================================================================

subtest 'filter aliases' => sub {
    is($Template::Filters::FILTERS->{evaltt}[0],
       $Template::Filters::FILTERS->{eval}[0],
       'evaltt factory same as eval');
    is($Template::Filters::FILTERS->{evalperl}[0],
       $Template::Filters::FILTERS->{perl}[0],
       'evalperl factory same as perl');
    is($Template::Filters::FILTERS->{file}[0],
       $Template::Filters::FILTERS->{redirect}[0],
       'file factory same as redirect');
    is($Template::Filters::FILTERS->{html_break},
       $Template::Filters::FILTERS->{html_para_break},
       'html_break is alias for html_para_break');
};


#========================================================================
# Integration: fetch through the full pipeline
#========================================================================

subtest 'fetch pipeline — dynamic filter end-to-end' => sub {
    my $f = Template::Filters->new({});
    my $ctx = MockContext->new();

    my $filter = $f->fetch('truncate', [10, '~'], $ctx);
    is(ref $filter, 'CODE', 'truncate filter fetched');
    is($filter->('short'), 'short', 'short text passes through');
    is($filter->('this is a very long string'), 'this is a~', 'truncated with custom addon');
};

subtest 'fetch pipeline — store then fetch' => sub {
    my $f = Template::Filters->new({});
    $f->store('reverse', sub { scalar reverse $_[0] });

    my $filter = $f->fetch('reverse', undef, undef);
    is($filter->('hello'), 'olleh', 'stored filter fetchable');
};

subtest 'fetch pipeline — store dynamic then fetch' => sub {
    my $f = Template::Filters->new({});
    $f->store('wrap', [ sub {
        my ($ctx, $left, $right) = @_;
        return sub { "$left$_[0]$right" };
    }, 1 ]);

    my $ctx = MockContext->new();
    my $filter = $f->fetch('wrap', ['[', ']'], $ctx);
    is($filter->('content'), '[content]', 'dynamic stored filter works with args');
};


done_testing();
