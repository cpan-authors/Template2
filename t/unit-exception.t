use strict;
use warnings;

use lib qw( ./lib ../lib );
use Test::More;
use Template::Exception;

#------------------------------------------------------------------------
# construction
#------------------------------------------------------------------------

{
    my $e = Template::Exception->new('file', 'not found');
    isa_ok($e, 'Template::Exception');
}

{
    my $text = 'some output';
    my $e = Template::Exception->new('parse', 'bad syntax', \$text);
    isa_ok($e, 'Template::Exception');
    is($e->text(), 'some output', 'text set via constructor');
}

{
    my $e = Template::Exception->new('undef', 'something went wrong', undef);
    isa_ok($e, 'Template::Exception');
    is($e->text(), '', 'undef textref yields empty string');
}

{
    my $e = Template::Exception->new('bare', 'no text arg');
    is($e->text(), '', 'no textref arg yields empty string');
}

#------------------------------------------------------------------------
# type() and info() accessors
#------------------------------------------------------------------------

{
    my $e = Template::Exception->new('file.open', 'cannot open /tmp/foo');
    is($e->type(), 'file.open',              'type accessor');
    is($e->info(), 'cannot open /tmp/foo',   'info accessor');
}

{
    my $e = Template::Exception->new('', '');
    is($e->type(), '', 'empty type');
    is($e->info(), '', 'empty info');
}

#------------------------------------------------------------------------
# type_info() returns list
#------------------------------------------------------------------------

{
    my $e = Template::Exception->new('mytype', 'myinfo');
    my @pair = $e->type_info();
    is(scalar @pair, 2, 'type_info returns two elements');
    is($pair[0], 'mytype', 'type_info first element is type');
    is($pair[1], 'myinfo', 'type_info second element is info');
}

#------------------------------------------------------------------------
# as_string()
#------------------------------------------------------------------------

{
    my $e = Template::Exception->new('plugin', 'Date not loaded');
    is($e->as_string(), 'plugin error - Date not loaded', 'as_string format');
}

{
    my $e = Template::Exception->new('', '');
    is($e->as_string(), ' error - ', 'as_string with empty type and info');
}

#------------------------------------------------------------------------
# stringification overload
#------------------------------------------------------------------------

{
    my $e = Template::Exception->new('file', 'missing');
    is("$e", 'file error - missing', 'string interpolation triggers as_string');
}

{
    my $e = Template::Exception->new('auth', 'denied');
    my $str = 'Error: ' . $e;
    is($str, 'Error: auth error - denied', 'concatenation triggers overload');
}

{
    my $e = Template::Exception->new('x', 'y');
    ok($e eq 'x error - y', 'eq comparison via overload');
    ok($e ne 'something else', 'ne comparison via overload');
}

#------------------------------------------------------------------------
# fallback overloading
#------------------------------------------------------------------------

{
    my $e = Template::Exception->new('test', 'val');
    ok($e, 'object is true in boolean context');
}

{
    my $e1 = Template::Exception->new('file', 'x');
    my $e2 = Template::Exception->new('parse', 'y');
    ok(($e1 cmp $e2) != 0, 'cmp distinguishes different exceptions');
    is(($e1 cmp $e1), 0,   'cmp same object equals itself');
}

#------------------------------------------------------------------------
# text() — prepend behavior
#------------------------------------------------------------------------

{
    my $original = 'world';
    my $e = Template::Exception->new('test', 'info', \$original);
    is($e->text(), 'world', 'text returns original content');

    my $prepend = 'hello ';
    my $result = $e->text(\$prepend);
    is($result, '', 'text() returns empty string after prepend');
    is($e->text(), 'hello world', 'text prepended to existing');
    is($prepend, 'hello world', 'prepend ref updated in place');
}

{
    my $t1 = 'C';
    my $e = Template::Exception->new('x', 'y', \$t1);

    my $t2 = 'B';
    $e->text(\$t2);

    my $t3 = 'A';
    $e->text(\$t3);

    is($e->text(), 'ABC', 'multiple prepends chain correctly');
}

{
    my $text = 'existing';
    my $e = Template::Exception->new('t', 'i', \$text);
    $e->text(\$text);
    is($e->text(), 'existing', 'same ref does not double content');
}

{
    my $e = Template::Exception->new('t', 'i');
    my $new = 'inserted';
    $e->text(\$new);
    is($e->text(), 'inserted', 'prepend to empty text works');
}

#------------------------------------------------------------------------
# select_handler() — hierarchical type matching
#------------------------------------------------------------------------

{
    my $e = Template::Exception->new('file.open', 'failed');
    is($e->select_handler('file.open'), 'file.open', 'exact match');
}

{
    my $e = Template::Exception->new('file.open.read', 'failed');
    is($e->select_handler('file.open', 'file', 'other'),
       'file.open', 'closest parent match');
}

{
    my $e = Template::Exception->new('file.open.read', 'failed');
    is($e->select_handler('file'), 'file', 'generic parent match');
}

{
    my $e = Template::Exception->new('file.open', 'failed');
    is($e->select_handler('parse', 'plugin', 'other'),
       undef, 'no match returns undef');
}

{
    my $e = Template::Exception->new('file.open', 'failed');
    is($e->select_handler(), undef, 'empty handler list returns undef');
}

{
    my $e = Template::Exception->new('a.b.c.d', 'deep');
    is($e->select_handler('a'), 'a', 'deeply nested walks up to root');
}

{
    my $e = Template::Exception->new('a.b.c.d', 'deep');
    is($e->select_handler('a.b'), 'a.b', 'deeply nested finds middle ancestor');
}

{
    my $e = Template::Exception->new('a.b.c.d', 'deep');
    is($e->select_handler('a.b.c.d', 'a.b.c', 'a.b', 'a'),
       'a.b.c.d', 'exact match preferred over ancestors');
}

{
    my $e = Template::Exception->new('foo', 'single');
    is($e->select_handler('foo'), 'foo', 'simple non-dotted type matches');
}

{
    my $e = Template::Exception->new('foo', 'single');
    is($e->select_handler('bar', 'baz'),
       undef, 'simple non-dotted type with no match');
}

{
    my $e = Template::Exception->new('foo.bar', 'info');
    my @handlers = ('other', 'foo', 'foo.bar');
    is($e->select_handler(@handlers), 'foo.bar',
       'exact match found even when generic appears first');
}

#------------------------------------------------------------------------
# info can hold a reference
#------------------------------------------------------------------------

{
    my $data = { code => 42, msg => 'oops' };
    my $e = Template::Exception->new('data', $data);
    is(ref($e->info()), 'HASH', 'info can be a hashref');
    is($e->info()->{code}, 42,   'info hashref accessible');
}

{
    my $list = [1, 2, 3];
    my $e = Template::Exception->new('data', $list);
    is(ref($e->info()), 'ARRAY', 'info can be an arrayref');
}

done_testing();
