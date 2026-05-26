#!/usr/bin/perl
#
# Unit tests for Template::Directive — the code generator that turns the
# parse tree into Perl code strings.  Each factory method takes structured
# input and returns a Perl source fragment; we test shape, key tokens,
# and (where practical) that the generated code compiles.

use strict;
use warnings;
use Test::More;

use Template::Directive;
use Template::Constants;

# Construct a Directive object the same way the Parser does.
my $d = Template::Directive->new({});
isa_ok($d, 'Template::Directive', 'constructor');

#-----------------------------------------------------------------------
# pad() — utility, not a method; called as pad($text, $level)
#-----------------------------------------------------------------------

subtest 'pad()' => sub {
    is(Template::Directive::pad("hello\nworld\n", 1),
       "    hello\n    world\n",
       'pad level 1 indents 4 spaces');

    is(Template::Directive::pad("a\nb\n", 2),
       "        a\n        b\n",
       'pad level 2 indents 8 spaces');

    my $with_line_directive = "#line 42 \"foo\"\ncode;\n";
    my $padded = Template::Directive::pad($with_line_directive, 1);
    like($padded, qr/^#line 42/m,   '#line directives are NOT padded');
    like($padded, qr/^    code;/m,  'other lines ARE padded');
};

#-----------------------------------------------------------------------
# text() — quote a literal string for embedding in generated Perl
#-----------------------------------------------------------------------

subtest 'text()' => sub {
    is($d->text('hello'), "'hello'", 'simple text uses single quotes');
    is($d->text(''), '', 'empty string returns empty');

    like($d->text('has $var'),    qr/^".*"$/,  'dollar sign triggers double quotes');
    like($d->text('has @arr'),    qr/^".*"$/,  'at sign triggers double quotes');
    like($d->text('back\\slash'), qr/^".*"$/,  'backslash triggers double quotes');

    my $q = $d->text("it's");
    like($q, qr/\\'/, 'single quote inside text is escaped');
    like($q, qr/^'.*'$/, 'still uses single quotes when only apostrophe');

    my $nl = $d->text("line1\nline2\$x");
    like($nl, qr/\\n/, 'newlines are escaped in double-quote mode');
};

#-----------------------------------------------------------------------
# textblock() — wraps text() output in $output .= ...;
#-----------------------------------------------------------------------

subtest 'textblock()' => sub {
    my $tb = $d->textblock('hello world');
    like($tb, qr/\$output \.\=/, 'assigns to $output');
    like($tb, qr/;$/,            'ends with semicolon');
    like($tb, qr/'hello world'/, 'contains the literal text');
};

#-----------------------------------------------------------------------
# quoted() — string interpolation: "foo $bar baz"
#-----------------------------------------------------------------------

subtest 'quoted()' => sub {
    is($d->quoted([]), '', 'empty list returns empty string');

    my $single = $d->quoted(['$stash->get(\'foo\')']);
    like($single, qr/^\('' \. /,  'single item gets empty-string prefix');

    my $multi = $d->quoted(["'hello '", '$stash->get(\'name\')']);
    like($multi, qr/^\(.*\)$/,    'multi items wrapped in parens');
    like($multi, qr/\./,          'joined with dot concatenation');
};

#-----------------------------------------------------------------------
# ident() — variable lookup code: foo.bar.baz
#-----------------------------------------------------------------------

subtest 'ident()' => sub {
    is($d->ident([]), "''", 'empty ident returns empty string');

    my $simple = $d->ident(["'foo'", 0]);
    like($simple, qr/\$stash->get\('foo'\)/, 'simple var uses scalar get');

    my $dotted = $d->ident(["'foo'", 0, "'bar'", 0]);
    like($dotted, qr/\$stash->get\(\[/, 'dotted var uses array-ref get');
    like($dotted, qr/'foo'.*'bar'/,     'contains both segments');

    my $with_args = $d->ident(["'method'", "[\$arg]"]);
    like($with_args, qr/\$stash->get\(\[/, 'method call with args uses array-ref');
};

subtest 'ident() with NAMESPACE' => sub {
    my $ns_handler = bless {}, 'MockNamespace';
    my $d_ns = Template::Directive->new({
        NAMESPACE => { constants => $ns_handler },
    });

    {
        no strict 'refs';
        *MockNamespace::ident = sub {
            my ($self, $ident) = @_;
            return 'NAMESPACE_RESOLVED';
        };
    }

    my $result = $d_ns->ident(["'constants'", 0, "'pi'", 0]);
    is($result, 'NAMESPACE_RESOLVED', 'NAMESPACE handler intercepts ident');
};

subtest 'ident() with TRACE_VARS' => sub {
    my $trace = {};
    my $d_trace = Template::Directive->new({});
    $d_trace->trace_vars($trace);

    $d_trace->ident(["'foo'", 0, "'bar'", 0]);
    ok(exists $trace->{foo},       'trace_vars records first segment');
    ok(exists $trace->{foo}{bar},  'trace_vars records second segment');
};

#-----------------------------------------------------------------------
# ident() called as class method (Template::Namespace::Constants does this)
#-----------------------------------------------------------------------

subtest 'ident() as class method' => sub {
    my $result = Template::Directive->ident(["'x'", 0]);
    like($result, qr/\$stash->get/, 'class method call still works');
};

#-----------------------------------------------------------------------
# identref() — reference to a variable: \foo.bar
#-----------------------------------------------------------------------

subtest 'identref()' => sub {
    is($d->identref([]), "''", 'empty identref returns empty string');

    my $simple = $d->identref(["'foo'", 0]);
    like($simple, qr/\$stash->getref\('foo'\)/, 'simple ref uses scalar getref');

    my $dotted = $d->identref(["'foo'", 0, "'bar'", 0]);
    like($dotted, qr/\$stash->getref\(\[/, 'dotted ref uses array-ref getref');
};

#-----------------------------------------------------------------------
# assign() — variable assignment code
#-----------------------------------------------------------------------

subtest 'assign()' => sub {
    my $set = $d->assign(["'x'", 0], '42');
    like($set, qr/\$stash->set\('x', 42\)/, 'simple assignment');

    my $default = $d->assign(["'x'", 0], '42', 1);
    like($default, qr/42, 1/, 'default flag appends , 1');

    my $dotted = $d->assign(["'a'", 0, "'b'", 0], '"val"');
    like($dotted, qr/\$stash->set\(\[.*\]/, 'dotted assignment uses array-ref');
};

#-----------------------------------------------------------------------
# args() — argument list builder
#-----------------------------------------------------------------------

subtest 'args()' => sub {
    my $none = $d->args([[]]);
    is($none, '0', 'no args returns 0');

    my $positional = $d->args([[], "'hello'", '42']);
    like($positional, qr/^\[ .* \]$/x, 'positional args in array ref');

    my $named = $d->args([["'name'", "'value'"]]);
    like($named, qr/\{.*'name'.*'value'.*\}/, 'named args produce hash ref');

    my $both = $d->args([["'k'", "'v'"], "'pos'"]);
    like($both, qr/'pos'/, 'positional args present');
    like($both, qr/\{.*'k'.*'v'.*\}/, 'named args present');
};

#-----------------------------------------------------------------------
# filenames() — file list handling
#-----------------------------------------------------------------------

subtest 'filenames()' => sub {
    is($d->filenames(["'one.tt'"]), "'one.tt'", 'single filename returned as-is');

    my $multi = $d->filenames(["'a.tt'", "'b.tt'"]);
    like($multi, qr/^\[.*\]$/, 'multiple filenames in array ref');
};

#-----------------------------------------------------------------------
# get() / call() — simple expression directives
#-----------------------------------------------------------------------

subtest 'get()' => sub {
    my $g = $d->get('$stash->get(\'foo\')');
    like($g, qr/\$output \.\=/, 'get() assigns to output');
    like($g, qr/;$/,            'ends with semicolon');
};

subtest 'call()' => sub {
    my $c = $d->call('$stash->get(\'foo\')');
    like($c, qr/;$/,              'call() ends with semicolon');
    unlike($c, qr/\$output \.\=/, 'call() does NOT assign to output');
};

#-----------------------------------------------------------------------
# set() / default()
#-----------------------------------------------------------------------

subtest 'set()' => sub {
    my $s = $d->set([["'x'", 0], '42', ["'y'", 0], '"hello"']);
    like($s, qr/\$stash->set\('x', 42\)/, 'first assignment');
    like($s, qr/\$stash->set\('y', "hello"\)/, 'second assignment');
};

subtest 'default()' => sub {
    my $def = $d->default([["'x'", 0], '42']);
    like($def, qr/42, 1/, 'default passes flag=1 to assign');
};

#-----------------------------------------------------------------------
# template() — the outermost wrapper
#-----------------------------------------------------------------------

subtest 'template()' => sub {
    my $empty = $d->template('   ');
    is($empty, "sub { return '' }", 'whitespace-only block returns empty sub');

    my $code = $d->template('$output .= "hello";');
    like($code, qr/^sub \{/,                   'starts with sub {');
    like($code, qr/my \$context = shift/,       'receives context');
    like($code, qr/my \$stash\s*=.*->stash/,   'gets stash from context');
    like($code, qr/my \$output\s*=\s*''/,       'initializes output');
    like($code, qr/eval \{ BLOCK:/,            'wraps in eval BLOCK');
    like($code, qr/return \$output/,            'returns output');
    like($code, qr/catch\(\$\@/,               'catches exceptions');

    # Verify the generated code compiles
    my $sub = eval $code;
    ok(ref $sub eq 'CODE', 'generated template code compiles to coderef');
};

#-----------------------------------------------------------------------
# anon_block()
#-----------------------------------------------------------------------

subtest 'anon_block()' => sub {
    my $code = $d->anon_block('$output .= "inner";');
    like($code, qr/\$output \.\=.*do \{/s,      'wraps in $output .= do { }');
    like($code, qr/my \$output\s*=\s*''/,        'creates local $output');
    like($code, qr/eval \{ BLOCK:/,              'has eval BLOCK');
};

#-----------------------------------------------------------------------
# block()
#-----------------------------------------------------------------------

subtest 'block()' => sub {
    is($d->block(undef),           '', 'undef block returns empty');
    is($d->block([]),              '', 'empty array returns empty');
    is($d->block(['a;', 'b;']),   "a;\nb;", 'joins elements with newline');
};

#-----------------------------------------------------------------------
# if() — conditionals
#-----------------------------------------------------------------------

subtest 'if()' => sub {
    my $simple_if = $d->if('$x', 'do_something();');
    like($simple_if, qr/if \(\$x\) \{/, 'if condition');
    like($simple_if, qr/do_something/,   'if body');

    my $if_else = $d->if('$x', 'true_branch;', ['false_branch;']);
    like($if_else, qr/if \(\$x\)/,  'if clause');
    like($if_else, qr/else \{/,     'else clause');
    like($if_else, qr/false_branch/, 'else body');

    my $if_elsif_else = $d->if('$a', 'block_a;',
        [['$b', 'block_b;'], 'block_else;']);
    like($if_elsif_else, qr/if \(\$a\)/,     'if clause');
    like($if_elsif_else, qr/elsif \(\$b\)/,  'elsif clause');
    like($if_elsif_else, qr/else \{/,         'else clause');
};

#-----------------------------------------------------------------------
# foreach()
#-----------------------------------------------------------------------

subtest 'foreach()' => sub {
    my $named = $d->foreach(
        'item',
        '$stash->get(\'list\')',
        [[]],
        '$output .= $stash->get(\'item\');',
    );
    like($named, qr/UNIVERSAL::isa.*Template::Iterator/, 'wraps non-iterators');
    like($named, qr/get_first/,                          'calls get_first');
    like($named, qr/get_next/,                           'calls get_next');
    like($named, qr/\$stash->\{'item'\}/,                'sets named loop var');
    like($named, qr/LOOP:\s*while/,                      'default LOOP label');

    my $unnamed = $d->foreach(
        undef,
        '$stash->get(\'list\')',
        [[]],
        '$output .= "body";',
    );
    like($unnamed, qr/localise/,    'unnamed foreach localises stash');
    like($unnamed, qr/delocalise/,  'unnamed foreach delocalises stash');
    like($unnamed, qr/import/,      'unnamed foreach imports hash values');

    my $labeled = $d->foreach('x', '$list', [[]], '$output .= "y";', 'OUTER');
    like($labeled, qr/OUTER:\s*while/, 'custom label used');
};

#-----------------------------------------------------------------------
# next()
#-----------------------------------------------------------------------

subtest 'next()' => sub {
    my $n = $d->next();
    like($n, qr/get_next/,    'advances iterator');
    like($n, qr/next LOOP/,   'default LOOP label');

    my $labeled = $d->next('OUTER');
    like($labeled, qr/next OUTER/, 'custom label');
};

#-----------------------------------------------------------------------
# while()
#-----------------------------------------------------------------------

subtest 'while()' => sub {
    my $w = $d->while('$x < 10', '$output .= $x++;');
    like($w, qr/\$_tt_failsafe/,                          'has failsafe counter');
    like($w, qr/while.*\$x < 10/,                         'condition present');
    like($w, qr/--\$_tt_failsafe >= 0/,                   'decrements failsafe');
    like($w, qr/WHILE loop terminated/,                    'throws on exhaustion');
    like($w, qr/LOOP:/,                                   'default LOOP label');

    my $labeled = $d->while('1', 'body;', 'INNER');
    like($labeled, qr/INNER:/, 'custom label');
};

subtest 'while() $WHILE_MAX' => sub {
    local $Template::Directive::WHILE_MAX = 500;
    my $w = $d->while('1', 'body;');
    like($w, qr/\$_tt_failsafe = 500/, 'uses current $WHILE_MAX value');
    like($w, qr/> 500\b/,              '$WHILE_MAX in error message');
};

#-----------------------------------------------------------------------
# switch()
#-----------------------------------------------------------------------

subtest 'switch()' => sub {
    my $sw = $d->switch('$x', [
        ["'foo'",  '$output .= "matched foo";'],
        ["'bar'",  '$output .= "matched bar";'],
        '$output .= "default";',
    ]);
    like($sw, qr/\$_tt_result = \$x/,       'evaluates switch expression');
    like($sw, qr/SWITCH:/,                   'SWITCH label');
    like($sw, qr/\$_tt_match = 'foo'/,       'first case match');
    like($sw, qr/\$_tt_match = 'bar'/,       'second case match');
    like($sw, qr/grep/,                      'uses grep for matching');
    like($sw, qr/last SWITCH/,              'breaks out of SWITCH');
    like($sw, qr/default/,                  'default block present');
};

subtest 'switch() without default' => sub {
    my $sw = $d->switch('$x', [
        ["'only'", '$output .= "only";'],
        undef,
    ]);
    unlike($sw, qr/else/, 'no default block when undef');
};

#-----------------------------------------------------------------------
# try() / catch
#-----------------------------------------------------------------------

subtest 'try()' => sub {
    my $try = $d->try(
        '$output .= "risky";',
        [
            ['file',  '$output .= "file error";'],
            [undef,   '$output .= "default catch";'],
            '$output .= "final";',
        ],
    );
    like($try, qr/eval \{/,                     'wraps in eval');
    like($try, qr/catch\(\$\@/,                 'catches exception');
    like($try, qr/select_handler/,               'uses select_handler');
    like($try, qr/\$_tt_handler eq 'file'/,      'file handler check');
    like($try, qr/set\('error'/,                 'sets error in stash');
    like($try, qr/set\('e'/,                     'sets e alias in stash');
    like($try, qr/return\|stop/,                 'rethrows return/stop');
    like($try, qr/# FINAL/,                      'final block present');
    like($try, qr/# DEFAULT/,                    'default catch present');
    like($try, qr/die \$_tt_error if \$_tt_error/, 'final rethrows if unhandled');
};

subtest 'try() without default catch' => sub {
    my $try = $d->try(
        '$output .= "risky";',
        [
            ['mytype', '$output .= "caught";'],
            '$output .= "final";',
        ],
    );
    like($try, qr/# NO DEFAULT/, 'no default marker when no default handler');
};

#-----------------------------------------------------------------------
# throw()
#-----------------------------------------------------------------------

subtest 'throw()' => sub {
    my $simple = $d->throw([["'myerror'"], [[], "'message'"]]);
    like($simple, qr/\$context->throw\('myerror', 'message'/, 'type and info');

    my $no_info = $d->throw([["'myerror'"], [[]]]);
    like($no_info, qr/\$context->throw\('myerror', undef/, 'type with undef info');

    my $with_args = $d->throw([["'myerror'"], [["'key'", "'val'"], "'info'", "'extra'"]]);
    like($with_args, qr/args =>/, 'args key present for multi-arg throw');
    like($with_args, qr/\\\$output/, 'passes output ref');
};

#-----------------------------------------------------------------------
# clear() / return() / stop()
#-----------------------------------------------------------------------

subtest 'clear()' => sub {
    is(Template::Directive::clear(), "\$output = '';", 'clears output');
};

subtest 'return()' => sub {
    like(Template::Directive::return(), qr/throw\('return'/, 'throws return');
};

subtest 'stop()' => sub {
    like(Template::Directive::stop(), qr/throw\('stop'/, 'throws stop');
};

#-----------------------------------------------------------------------
# insert() / include() / process()
#-----------------------------------------------------------------------

subtest 'insert()' => sub {
    my $ins = $d->insert([["'header.tt'"], []]);
    like($ins, qr/\$context->insert\('header.tt'\)/, 'inserts file');
    like($ins, qr/\$output \.\=/, 'assigns to output');
};

subtest 'include()' => sub {
    my $inc = $d->include([["'page.tt'"], [[], "'x'", '42']]);
    like($inc, qr/\$context->include\('page.tt'\)/, 'includes file');

    my $with_hash = $d->include([["'page.tt'"], [["'title'", "'hello'"]]]);
    like($with_hash, qr/include\('page.tt', \{.*'title'.*'hello'/, 'passes hash args');
};

subtest 'process()' => sub {
    my $proc = $d->process([["'tmpl.tt'"], [[]]]);
    like($proc, qr/\$context->process\('tmpl.tt'\)/, 'processes file');
};

#-----------------------------------------------------------------------
# use()
#-----------------------------------------------------------------------

subtest 'use()' => sub {
    my $use = $d->use([["'Date'"], [[], []], undef]);
    like($use, qr/# USE/,                    'USE comment');
    like($use, qr/\$context->plugin\('Date'/, 'loads plugin');
    like($use, qr/\$stash->set\('Date'/,      'stores under plugin name');

    my $aliased = $d->use([["'Date'"], [[], []], "'d'"]);
    like($aliased, qr/\$stash->set\('d'/, 'stores under alias');
};

#-----------------------------------------------------------------------
# wrapper() / multi_wrapper()
#-----------------------------------------------------------------------

subtest 'wrapper()' => sub {
    my $wrap = $d->wrapper(
        [["'layout.tt'"], [[]]],
        '$output .= "inner";',
    );
    like($wrap, qr/# WRAPPER/,                'WRAPPER comment');
    like($wrap, qr/my \$output = ''/,          'local output');
    like($wrap, qr/'content'/,                 'passes content');
    like($wrap, qr/\$context->include\('layout.tt'/, 'includes wrapper');
};

subtest 'multi_wrapper()' => sub {
    my $wrap = $d->wrapper(
        [["'outer.tt'", "'inner.tt'"], [[]]],
        '$output .= "body";',
    );
    like($wrap, qr/foreach/,  'multi wrapper iterates');
    like($wrap, qr/'content'/, 'passes content');
};

#-----------------------------------------------------------------------
# filter()
#-----------------------------------------------------------------------

subtest 'filter()' => sub {
    my $filt = $d->filter(
        [["'html'"], [[], []], undef],
        '$output .= "raw <b> content";',
    );
    like($filt, qr/# FILTER/,                  'FILTER comment');
    like($filt, qr/\$context->filter\('html'/, 'fetches filter');
    like($filt, qr/&\$_tt_filter\(\$output\)/,  'applies filter to output');

    my $aliased = $d->filter(
        [["'html'"], [[], []], "'myfilter'"],
        '$output .= "content";',
    );
    like($aliased, qr/'myfilter'/, 'alias passed to filter');
};

#-----------------------------------------------------------------------
# capture()
#-----------------------------------------------------------------------

subtest 'capture()' => sub {
    my $cap = $d->capture(["'result'", 0], '$output .= "captured";');
    like($cap, qr/# CAPTURE/,              'CAPTURE comment');
    like($cap, qr/\$stash->set\('result'/, 'sets capture var');
    like($cap, qr/my \$output = ''/,        'local output');
    like($cap, qr/\$output;/,               'returns local output');

    my $dotted = $d->capture(["'a'", 0, "'b'", 0], 'code;');
    like($dotted, qr/\$stash->set\(\[/, 'dotted capture uses array-ref');
};

#-----------------------------------------------------------------------
# macro()
#-----------------------------------------------------------------------

subtest 'macro() without args' => sub {
    my $mac = $d->macro('mymacro', '$output .= "body";');
    like($mac, qr/# MACRO/,                    'MACRO comment');
    like($mac, qr/\$stash->set\('mymacro'/,    'stores macro in stash');
    like($mac, qr/sub \{/,                      'creates anonymous sub');
    like($mac, qr/localise/,                    'localises stash');
    like($mac, qr/delocalise/,                  'delocalises stash');
    like($mac, qr/return \$output/,             'returns output');
};

subtest 'macro() with args' => sub {
    my $mac = $d->macro('greet', '$output .= "hi";', ['name', 'title']);
    like($mac, qr/'name'.*'title'/,            'arg names present');
    like($mac, qr/splice\(\@_, 0, 2\)/,        'splices positional args');
    like($mac, qr/\$_tt_params/,               'handles extra hash params');
};

subtest 'macro() with single arg' => sub {
    my $mac = $d->macro('single', '$output .= "x";', ['arg']);
    like($mac, qr/\$_tt_args\{ 'arg' \} = shift/, 'single arg uses shift');
};

#-----------------------------------------------------------------------
# view()
#-----------------------------------------------------------------------

subtest 'view()' => sub {
    my $view = $d->view(
        [["'myview'"], [[]]],
        '$output .= "viewblock";',
        {},
    );
    like($view, qr/# VIEW/,                   'VIEW comment');
    like($view, qr/\$context->view/,           'creates view via context');
    like($view, qr/\$stash->set\('myview'/,    'stores view in stash');
    like($view, qr/seal\(\)/,                  'seals view');
    like($view, qr/\$_tt_oldv/,                'saves old view');
    like($view, qr/set\('view', \$_tt_oldv\)/, 'restores old view');
};

subtest 'view() with defblocks' => sub {
    my $view = $d->view(
        [["'v'"], [[]]],
        '',
        { 'greeting' => 'sub { "hi" }' },
    );
    like($view, qr/'blocks'/, 'passes blocks hash');
    like($view, qr/'greeting'/, 'block name present');
};

#-----------------------------------------------------------------------
# perl() / no_perl() / rawperl()
#-----------------------------------------------------------------------

subtest 'perl()' => sub {
    my $p = $d->perl('$output .= "print 42;\n";');
    like($p, qr/# PERL/,                  'PERL comment');
    like($p, qr/eval_perl/,                'checks EVAL_PERL');
    like($p, qr/Template::Perl/,           'uses Template::Perl namespace');
    like($p, qr/tie \*Template::Perl/,     'ties PERLOUT');
    like($p, qr/eval \$output/,            'evals the code');
};

subtest 'no_perl()' => sub {
    like($d->no_perl(), qr/throw\('perl'/, 'throws perl error');
    like($d->no_perl(), qr/EVAL_PERL/,     'mentions EVAL_PERL');
};

subtest 'rawperl()' => sub {
    my $rp = $d->rawperl("\ncode_here();\n", 42);
    like($rp, qr/# RAWPERL/,            'RAWPERL comment');
    like($rp, qr/#line 1/,              '#line directive');
    like($rp, qr/starting line 42/,     'source line number');
    like($rp, qr/code_here\(\)/,        'code block present');

    my $rp_noline = $d->rawperl("x();");
    unlike($rp_noline, qr/starting line/, 'no line number when not given');
};

#-----------------------------------------------------------------------
# debug()
#-----------------------------------------------------------------------

subtest 'debug()' => sub {
    my $dbg = $d->debug([["'on'"], [[], []]]);
    like($dbg, qr/\$context->debugging/, 'calls debugging method');
    like($dbg, qr/## DEBUG ##/,           'DEBUG marker');
};

#-----------------------------------------------------------------------
# $PRETTY mode
#-----------------------------------------------------------------------

subtest '$PRETTY mode' => sub {
    local $Template::Directive::PRETTY = 1;

    my $tmpl = $d->template('$output .= "hello";');
    like($tmpl, qr/^        /m, 'template block indented at level 2');

    my $if_code = $d->if('1', 'body;');
    like($if_code, qr/^    body;/m, 'if block indented at level 1');

    $Template::Directive::PRETTY = 0;
};

#-----------------------------------------------------------------------
# trace_vars() accessor
#-----------------------------------------------------------------------

subtest 'trace_vars()' => sub {
    is($d->trace_vars, undef, 'initially undef');

    my $hash = {};
    $d->trace_vars($hash);
    is($d->trace_vars, $hash, 'getter returns set value');

    $d->trace_vars(undef);
};

#-----------------------------------------------------------------------
# Package variables
#-----------------------------------------------------------------------

subtest 'package variables' => sub {
    ok(defined $Template::Directive::VERSION,    'VERSION defined');
    is($Template::Directive::WHILE_MAX, 1000,    'default WHILE_MAX is 1000');
    is($Template::Directive::PRETTY,    0,       'default PRETTY is 0');
    is($Template::Directive::OUTPUT,    '$output .= ', 'OUTPUT prefix');
};

done_testing();
