#!/usr/bin/perl -w
#
# t/service_methods.t
#
# Unit tests for Template::Service: constructor config parsing,
# process() pipeline (PRE_PROCESS, PROCESS, WRAPPER, POST_PROCESS),
# context() accessor, _recover() error dispatch, AUTO_RESET, DEBUG.
#

use strict;
use lib qw( ./lib ../lib );
use Test::More tests => 78;

use Template;
use Template::Service;
use Template::Context;
use Template::Config;
use Template::Exception;
use Template::Constants qw( :debug );

my $dir = -d 't' ? 't/test' : 'test';

#------------------------------------------------------------------------
# constructor — defaults
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    ok(defined $svc, 'constructor succeeds with minimal config');
    isa_ok($svc, 'Template::Service');

    is_deeply($svc->{ PRE_PROCESS }, [], 'PRE_PROCESS defaults to empty array');
    is_deeply($svc->{ POST_PROCESS }, [], 'POST_PROCESS defaults to empty array');
    is($svc->{ PROCESS }, undef, 'PROCESS defaults to undef (use input template)');
    is_deeply($svc->{ WRAPPER }, [], 'WRAPPER defaults to empty array');
    is($svc->{ AUTO_RESET }, 1, 'AUTO_RESET defaults to 1');
    is($svc->{ DEBUG }, 0, 'DEBUG defaults to 0');
}

#------------------------------------------------------------------------
# constructor — string to array coercion
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        PRE_PROCESS  => 'header',
        POST_PROCESS => 'footer',
        PROCESS      => 'content',
        WRAPPER      => 'outer',
    });
    is_deeply($svc->{ PRE_PROCESS }, ['header'], 'PRE_PROCESS string coerced to array');
    is_deeply($svc->{ POST_PROCESS }, ['footer'], 'POST_PROCESS string coerced to array');
    is_deeply($svc->{ PROCESS }, ['content'], 'PROCESS string coerced to array');
    is_deeply($svc->{ WRAPPER }, ['outer'], 'WRAPPER string coerced to array');
}

#------------------------------------------------------------------------
# constructor — arrays passed through
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        PRE_PROCESS  => ['config', 'header'],
        POST_PROCESS => ['footer'],
        WRAPPER      => ['outer', 'inner'],
    });
    is_deeply($svc->{ PRE_PROCESS }, ['config', 'header'], 'PRE_PROCESS array preserved');
    is_deeply($svc->{ POST_PROCESS }, ['footer'], 'POST_PROCESS array preserved');
    is_deeply($svc->{ WRAPPER }, ['outer', 'inner'], 'WRAPPER array preserved');
}

#------------------------------------------------------------------------
# constructor — custom DELIMITER for string splitting
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        DELIMITER    => ',',
        PRE_PROCESS  => 'config,header',
        POST_PROCESS => 'footer',
    });
    is_deeply($svc->{ PRE_PROCESS }, ['config', 'header'],
        'DELIMITER splits PRE_PROCESS on comma');
    is_deeply($svc->{ POST_PROCESS }, ['footer'],
        'DELIMITER splits POST_PROCESS on comma');
}

#------------------------------------------------------------------------
# constructor — ERROR / ERRORS
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERROR => { barf => 'barfed', default => 'error' },
    });
    is(ref $svc->{ ERROR }, 'HASH', 'ERROR hash stored correctly');
    is($svc->{ ERROR }{ barf }, 'barfed', 'ERROR handler for barf');

    my $svc2 = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERRORS => 'catch_all',
    });
    is($svc2->{ ERROR }, 'catch_all', 'ERRORS alias accepted');
}

#------------------------------------------------------------------------
# constructor — AUTO_RESET can be disabled
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        AUTO_RESET => 0,
    });
    is($svc->{ AUTO_RESET }, 0, 'AUTO_RESET can be set to 0');
}

#------------------------------------------------------------------------
# constructor — DEBUG flag
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        DEBUG => DEBUG_SERVICE,
    });
    ok($svc->{ DEBUG }, 'DEBUG_SERVICE enables debug output');

    my $svc2 = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        DEBUG => DEBUG_PROVIDER,
    });
    is($svc2->{ DEBUG }, 0, 'DEBUG_PROVIDER does not enable service debug');
}

#------------------------------------------------------------------------
# constructor — CONTEXT passed in
#------------------------------------------------------------------------

{
    my $ctx = Template::Context->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $svc = Template::Service->new({
        CONTEXT => $ctx,
    });
    is($svc->context, $ctx, 'passed CONTEXT used directly');
}

#------------------------------------------------------------------------
# context() accessor
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $ctx = $svc->context();
    isa_ok($ctx, 'Template::Context');
    is($svc->context(), $ctx, 'context() returns same object on repeated calls');
}

#------------------------------------------------------------------------
# process() — basic template
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $output = $svc->process(\'Hello [% name %]', { name => 'World' });
    ok(defined $output, 'process() returns defined output');
    is($output, 'Hello World', 'process() interpolates variables');
}

#------------------------------------------------------------------------
# process() — PRE_PROCESS and POST_PROCESS
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        PRE_PROCESS  => ['config', 'header'],
        POST_PROCESS => 'footer',
    });
    my $output = $svc->process(\'body content', { title => 'Test' });
    ok(defined $output, 'process with PRE/POST_PROCESS returns output');
    like($output, qr/header.*body content.*footer/s,
        'PRE_PROCESS prepended, POST_PROCESS appended');
}

#------------------------------------------------------------------------
# process() — WRAPPER
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });

    # Create a template string that acts as a wrapper
    my $wrapper_src = '[% content %]';
    my $inner_src   = 'inner stuff';

    # Test wrapping via the Template interface (which uses Service)
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        WRAPPER      => 'outer',
    });
    my $out = '';
    $tt->process(\q{[% title = 'Wrap Test' -%]wrapped body}, {}, \$out);
    like($out, qr/outer/i, 'WRAPPER template applied')
        or diag("WRAPPER output: $out");
}

#------------------------------------------------------------------------
# process() — nested WRAPPERs (reverse order)
#------------------------------------------------------------------------

{
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        WRAPPER      => ['outer', 'inner'],
    });
    my $out = '';
    $tt->process(\q{[% title = 'Nested' -%]content here}, {}, \$out);
    like($out, qr/outer.*inner.*content here/si,
        'nested WRAPPERs applied in reverse (outer wraps inner wraps content)')
        or diag("nested output: $out");
}

#------------------------------------------------------------------------
# process() — PROCESS overrides input template
#------------------------------------------------------------------------

{
    my $tt = Template->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        PROCESS      => 'process',
    });
    my $out = '';
    my $ok = $tt->process(\q{[% title = 'Override Test' -%]original}, {}, \$out);
    ok($ok, 'PROCESS config processes successfully');
    # The 'process' template wraps content; original template available as $template
    like($out, qr/process/i, 'PROCESS template used instead of input template')
        or diag("PROCESS output: $out");
}

#------------------------------------------------------------------------
# process() — template variable set in stash
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $output = $svc->process(\'[% template.name %]');
    ok(defined $output, 'process with template metadata succeeds');
    # template name for string refs is 'input text'
    like($output, qr/input text/, 'template variable set in stash for string input');
}

#------------------------------------------------------------------------
# process() — code ref template: no 'template' variable set
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    # Code ref template — 'template' should not be set in params
    my $code_tmpl = sub { return 'code output' };
    my $output = $svc->process($code_tmpl);
    is($output, 'code output', 'code ref template processed directly');
}

#------------------------------------------------------------------------
# process() — params merged into stash
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $output = $svc->process(
        \'[% greeting %] [% target %]',
        { greeting => 'Hi', target => 'there' },
    );
    is($output, 'Hi there', 'params passed to process merged into stash');
}

#------------------------------------------------------------------------
# process() — localise/delocalise: params don't leak between calls
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    $svc->process(\'[% x %]', { x => 'first' });
    my $output = $svc->process(\'>[% x %]<');
    is($output, '><', 'params from previous call do not leak into next call');
}

#------------------------------------------------------------------------
# process() — AUTO_RESET behavior
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        AUTO_RESET   => 1,
    });
    # Define a block in first call
    $svc->process(\'[% BLOCK myblock %]hello[% END %]');
    # With AUTO_RESET, it should be gone in the next call
    my $output = $svc->process(\'[% TRY; INCLUDE myblock; CATCH; "gone"; END %]');
    is($output, 'gone', 'AUTO_RESET clears blocks between calls');
}

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        AUTO_RESET   => 0,
    });
    $svc->process(\'[% BLOCK persistent %]still here[% END %]');
    my $output = $svc->process(\'[% INCLUDE persistent %]');
    is($output, 'still here', 'AUTO_RESET=0 preserves blocks between calls');
}

#------------------------------------------------------------------------
# process() — bad template returns undef with error
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $output = $svc->process('nonexistent_template_xyz');
    ok(!defined $output, 'process returns undef for missing template');
    like($svc->error(), qr/not found/, 'error message mentions not found');
}

#------------------------------------------------------------------------
# process() — error in PRE_PROCESS fails the service
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        PRE_PROCESS  => 'no_such_pre_process_template',
    });
    my $output = $svc->process(\'body');
    ok(!defined $output, 'bad PRE_PROCESS template causes failure');
    like($svc->error(), qr/no_such_pre_process_template/,
        'error mentions the bad PRE_PROCESS template');
}

#------------------------------------------------------------------------
# process() — error in POST_PROCESS fails the service
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        POST_PROCESS => 'no_such_post_process_template',
    });
    my $output = $svc->process(\'body');
    ok(!defined $output, 'bad POST_PROCESS template causes failure');
    like($svc->error(), qr/no_such_post_process_template/,
        'error mentions the bad POST_PROCESS template');
}

#------------------------------------------------------------------------
# process() — ERROR handler catches template exceptions
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERROR => {
            barf    => 'barfed',
            default => 'error',
        },
    });
    my $output = $svc->process(\'[% THROW barf "ugh" %]');
    ok(defined $output, 'ERROR handler catches barf exception');
    like($output, qr/barf/, 'error template rendered for barf exception');
}

#------------------------------------------------------------------------
# process() — ERROR scalar catches all exceptions
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERROR => 'barfed',
    });
    my $output = $svc->process(\'[% THROW anything "catch me" %]');
    ok(defined $output, 'scalar ERROR handler catches exception');
    like($output, qr/anything/, 'error template rendered for any exception');
}

#------------------------------------------------------------------------
# process() — STOP exception returns accumulated output
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $output = $svc->process(\'before[% STOP %]after');
    ok(defined $output, 'STOP does not cause error');
    like($output, qr/before/, 'output before STOP is preserved');
    unlike($output, qr/after/, 'output after STOP is not included');
}

#------------------------------------------------------------------------
# _recover() — non-exception: returns undef
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERROR => 'barfed',
    });
    my $plain_error = "just a string";
    my $result = $svc->_recover(\$plain_error);
    ok(!defined $result, '_recover returns undef for non-exception error');
}

#------------------------------------------------------------------------
# _recover() — stop exception: returns text
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $text = 'accumulated output';
    my $stop = Template::Exception->new('stop', 'halted', \$text);
    my $result = $svc->_recover(\$stop);
    is($result, 'accumulated output', '_recover returns text for stop exception');
}

#------------------------------------------------------------------------
# _recover() — no ERROR handlers: returns undef
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $ex = Template::Exception->new('user', 'bad input');
    my $result = $svc->_recover(\$ex);
    ok(!defined $result, '_recover returns undef when no ERROR handlers defined');
}

#------------------------------------------------------------------------
# _recover() — hash handler with matching type
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERROR => { barf => 'barfed', default => 'error' },
    });
    my $ex = Template::Exception->new('barf', 'Not feeling well');
    my $result = $svc->_recover(\$ex);
    ok(defined $result, '_recover finds handler for barf type');
    like($result, qr/barf/, '_recover processes barf error template');
}

#------------------------------------------------------------------------
# _recover() — hash handler with default fallback
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERROR => { barf => 'barfed', default => 'error' },
    });
    my $ex = Template::Exception->new('unknown', 'mystery error');
    my $result = $svc->_recover(\$ex);
    ok(defined $result, '_recover falls back to default handler');
    like($result, qr/unknown/, 'default error template rendered for unknown type');
}

#------------------------------------------------------------------------
# _recover() — hash handler with no match and no default
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERROR => { barf => 'barfed' },
    });
    my $ex = Template::Exception->new('other', 'no handler here');
    my $result = $svc->_recover(\$ex);
    ok(!defined $result, '_recover returns undef when no matching handler and no default');
}

#------------------------------------------------------------------------
# _recover() — scalar handler (catch-all)
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERROR => 'barfed',
    });
    my $ex = Template::Exception->new('anything', 'some error');
    my $result = $svc->_recover(\$ex);
    ok(defined $result, '_recover uses scalar handler as catch-all');
    like($result, qr/anything/, 'catch-all error template rendered');
}

#------------------------------------------------------------------------
# _recover() — handler template not found
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERROR => 'nonexistent_error_template',
    });
    my $ex = Template::Exception->new('fail', 'original error');
    my $result = $svc->_recover(\$ex);
    ok(!defined $result, '_recover returns undef when handler template not found');
}

#------------------------------------------------------------------------
# _recover() — hierarchical exception matching
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        ERROR => { user => 'barfed', default => 'error' },
    });
    # user.auth should match 'user' handler via select_handler hierarchy
    my $ex = Template::Exception->new('user.auth', 'not logged in');
    my $result = $svc->_recover(\$ex);
    ok(defined $result, '_recover matches hierarchical exception type');
    like($result, qr/user\.auth/,
        'hierarchical exception dispatched to parent handler');
}

#------------------------------------------------------------------------
# process() — multiple PRE_PROCESS templates execute in order
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        PRE_PROCESS  => ['config', 'header'],
        POST_PROCESS => 'footer',
    });
    my $output = $svc->process(\'main content', { title => 'Order Test' });
    ok(defined $output, 'multiple PRE_PROCESS templates processed');
    # config sets 'menu', header uses it
    like($output, qr/menu/, 'config PRE_PROCESS runs before header');
}

#------------------------------------------------------------------------
# process() — PROCESS with multiple templates
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        PROCESS      => ['header', 'footer'],
    });
    my $output = $svc->process(\'ignored body', { title => 'Multi' });
    ok(defined $output, 'multiple PROCESS templates work');
    like($output, qr/header/i, 'first PROCESS template included');
    like($output, qr/footer/i, 'second PROCESS template included');
}

#------------------------------------------------------------------------
# process() — DEBUG output
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        PRE_PROCESS  => 'header',
        POST_PROCESS => 'footer',
        DEBUG        => DEBUG_SERVICE,
    });
    # Should not die with debug enabled
    my $output = $svc->process(\'debug test', { title => 'Debug' });
    ok(defined $output, 'process succeeds with DEBUG_SERVICE enabled');
}

#------------------------------------------------------------------------
# constructor — context creation failure returns error
#------------------------------------------------------------------------

{
    # Provide a bogus CONTEXT configuration that will fail
    local $Template::Config::CONTEXT = 'Totally::Bogus::Module';
    my $svc = Template::Service->new({});
    ok(!defined $svc, 'constructor fails with bad CONTEXT config');
    like(Template::Service->error(), qr/Totally::Bogus/i,
        'error propagated from failed context creation');
}

#------------------------------------------------------------------------
# process() — stash delocalised even on error
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
    });
    my $stash = $svc->context->stash;
    $stash->set('marker', 'original');

    # Process a template that throws - localisation still unwound
    $svc->process(\'[% THROW test "boom" %]', { marker => 'temporary' });

    is($stash->get('marker'), 'original',
        'stash delocalised even after exception');
}

#------------------------------------------------------------------------
# process() — error in WRAPPER fails the service
#------------------------------------------------------------------------

{
    my $svc = Template::Service->new({
        INCLUDE_PATH => "$dir/src:$dir/lib",
        WRAPPER      => 'no_such_wrapper_template',
    });
    my $output = $svc->process(\'body');
    ok(!defined $output, 'bad WRAPPER template causes failure');
    like($svc->error(), qr/no_such_wrapper_template/,
        'error mentions the bad WRAPPER template');
}
