use strict;
use warnings;

use lib qw( ./lib ../lib );
use Test::More;
use Scalar::Util qw( blessed );
use Template::VMethods;

#------------------------------------------------------------------------
# root virtual methods
#------------------------------------------------------------------------

subtest 'root_inc' => sub {
    is(Template::VMethods::root_inc(0), 1, 'inc 0');
    is(Template::VMethods::root_inc(41), 42, 'inc 41');
    is(Template::VMethods::root_inc(-1), 0, 'inc -1');
    is(Template::VMethods::root_inc(1.5), 2.5, 'inc float');
};

subtest 'root_dec' => sub {
    is(Template::VMethods::root_dec(1), 0, 'dec 1');
    is(Template::VMethods::root_dec(0), -1, 'dec 0');
    is(Template::VMethods::root_dec(42), 41, 'dec 42');
    is(Template::VMethods::root_dec(1.5), 0.5, 'dec float');
};

#------------------------------------------------------------------------
# text virtual methods
#------------------------------------------------------------------------

subtest 'text_item' => sub {
    is(Template::VMethods::text_item('hello'), 'hello', 'returns self');
    is(Template::VMethods::text_item(''), '', 'empty string');
};

subtest 'text_list' => sub {
    my $result = Template::VMethods::text_list('hello');
    is_deeply($result, ['hello'], 'wraps in arrayref');
    $result = Template::VMethods::text_list('');
    is_deeply($result, [''], 'wraps empty string');
};

subtest 'text_hash' => sub {
    my $result = Template::VMethods::text_hash('hello');
    is_deeply($result, { value => 'hello' }, 'wraps in hashref with value key');
};

subtest 'text_length' => sub {
    is(Template::VMethods::text_length('hello'), 5, 'length of hello');
    is(Template::VMethods::text_length(''), 0, 'length of empty');
    is(Template::VMethods::text_length('a'), 1, 'length of single char');
};

subtest 'text_size' => sub {
    is(Template::VMethods::text_size('anything'), 1, 'always returns 1');
    is(Template::VMethods::text_size(''), 1, 'even for empty string');
};

subtest 'text_empty' => sub {
    is(Template::VMethods::text_empty(''), 1, 'empty string is empty');
    is(Template::VMethods::text_empty('x'), 0, 'non-empty string is not empty');
};

subtest 'text_defined' => sub {
    is(Template::VMethods::text_defined('hello'), 1, 'always returns 1');
    is(Template::VMethods::text_defined(''), 1, 'even for empty');
};

subtest 'text_upper' => sub {
    is(Template::VMethods::text_upper('hello'), 'HELLO', 'uppercases');
    is(Template::VMethods::text_upper('Hello World'), 'HELLO WORLD', 'mixed case');
    is(Template::VMethods::text_upper('ALREADY'), 'ALREADY', 'already upper');
};

subtest 'text_lower' => sub {
    is(Template::VMethods::text_lower('HELLO'), 'hello', 'lowercases');
    is(Template::VMethods::text_lower('Hello World'), 'hello world', 'mixed case');
};

subtest 'text_ucfirst' => sub {
    is(Template::VMethods::text_ucfirst('hello'), 'Hello', 'ucfirsts');
    is(Template::VMethods::text_ucfirst(''), '', 'empty string');
    is(Template::VMethods::text_ucfirst('a'), 'A', 'single char');
};

subtest 'text_lcfirst' => sub {
    is(Template::VMethods::text_lcfirst('Hello'), 'hello', 'lcfirsts');
    is(Template::VMethods::text_lcfirst(''), '', 'empty string');
    is(Template::VMethods::text_lcfirst('A'), 'a', 'single char');
};

subtest 'text_trim' => sub {
    is(Template::VMethods::text_trim('  hello  '), 'hello', 'trims both sides');
    is(Template::VMethods::text_trim("  hello\n"), 'hello', 'trims whitespace chars');
    is(Template::VMethods::text_trim('hello'), 'hello', 'no-op on clean string');
    is(Template::VMethods::text_trim(''), '', 'empty string');
    is(Template::VMethods::text_trim("  inner  space  "), 'inner  space', 'preserves inner space');

    my $orig = '  original  ';
    Template::VMethods::text_trim($orig);
    is($orig, '  original  ', 'does not mutate input');
};

subtest 'text_collapse' => sub {
    is(Template::VMethods::text_collapse('  hello   world  '), 'hello world', 'collapses whitespace');
    is(Template::VMethods::text_collapse("  a\n\tb  "), 'a b', 'collapses mixed whitespace');
    is(Template::VMethods::text_collapse('hello'), 'hello', 'no-op on clean string');
    is(Template::VMethods::text_collapse(''), '', 'empty string');

    my $orig = '  original  value  ';
    Template::VMethods::text_collapse($orig);
    is($orig, '  original  value  ', 'does not mutate input');
};

subtest 'text_match' => sub {
    my $result = Template::VMethods::text_match('hello world', 'o');
    is_deeply($result, [1], 'non-global match without captures returns [1]');

    $result = Template::VMethods::text_match('hello world', 'o', 1);
    is_deeply($result, ['o', 'o'], 'global match returns all');

    $result = Template::VMethods::text_match('hello world', '(\\w+)');
    is_deeply($result, ['hello'], 'capture group');

    $result = Template::VMethods::text_match('hello world', '(\\w+)', 1);
    is_deeply($result, ['hello', 'world'], 'global capture');

    $result = Template::VMethods::text_match('hello', 'xyz');
    is($result, '', 'no match returns empty string');

    $result = Template::VMethods::text_match(undef, 'x');
    is($result, undef, 'undef str returns undef');

    $result = Template::VMethods::text_match('hello', undef);
    is($result, 'hello', 'undef search returns str');
};

subtest 'text_search' => sub {
    ok(Template::VMethods::text_search('hello world', 'world'), 'found');
    ok(!Template::VMethods::text_search('hello world', 'xyz'), 'not found');
    ok(Template::VMethods::text_search('hello world', 'hel+o'), 'regex search');

    is(Template::VMethods::text_search(undef, 'x'), undef, 'undef str');
    is(Template::VMethods::text_search('hello', undef), 'hello', 'undef pattern');
};

subtest 'text_repeat' => sub {
    is(Template::VMethods::text_repeat('ab', 3), 'ababab', 'repeat 3 times');
    is(Template::VMethods::text_repeat('x', 1), 'x', 'repeat once');
    is(Template::VMethods::text_repeat('x', 0), '', 'repeat 0 times');
    is(Template::VMethods::text_repeat(undef, 3), '', 'undef str');
};

subtest 'text_replace' => sub {
    is(Template::VMethods::text_replace('hello world', 'world', 'there'),
        'hello there', 'simple replace');

    is(Template::VMethods::text_replace('aaa', 'a', 'b'),
        'bbb', 'global by default');

    is(Template::VMethods::text_replace('aaa', 'a', 'b', 0),
        'baa', 'non-global');

    is(Template::VMethods::text_replace('foo bar', '(\\w+)', '$1!'),
        'foo! bar!', 'backreference replace');

    is(Template::VMethods::text_replace('foo bar', '(\\w+)', '$1!', 0),
        'foo! bar', 'backreference non-global');

    is(Template::VMethods::text_replace(undef, 'a', 'b'), '', 'undef text');
    is(Template::VMethods::text_replace('hello', undef, 'x'),
        'xhxexlxlxox', 'undef pattern becomes empty string, matches every position');
};

subtest 'text_remove' => sub {
    is(Template::VMethods::text_remove('hello world', 'o'), 'hell wrld', 'removes globally');
    is(Template::VMethods::text_remove('hello', 'xyz'), 'hello', 'no match');
    is(Template::VMethods::text_remove(undef, 'x'), undef, 'undef str');
    is(Template::VMethods::text_remove('hello', undef), 'hello', 'undef search');
};

subtest 'text_split' => sub {
    is_deeply(Template::VMethods::text_split('a,b,c', ','), ['a', 'b', 'c'], 'split on comma');
    is_deeply(Template::VMethods::text_split('a,b,c', ',', 2), ['a', 'b,c'], 'split with limit');
    is_deeply(Template::VMethods::text_split('a  b  c'), ['a', 'b', 'c'], 'default split on whitespace');
    is_deeply(Template::VMethods::text_split(''), [], 'split empty string yields empty list');
    is_deeply(Template::VMethods::text_split(undef, ','), [], 'split undef yields empty list');
};

subtest 'text_chunk' => sub {
    is_deeply(Template::VMethods::text_chunk('abcdef', 2), ['ab', 'cd', 'ef'], 'chunk by 2');
    is_deeply(Template::VMethods::text_chunk('abcde', 2), ['ab', 'cd', 'e'], 'chunk with remainder');
    is_deeply(Template::VMethods::text_chunk('abcde', -2), ['a', 'bc', 'de'], 'negative chunk from right');
    is_deeply(Template::VMethods::text_chunk('abc', 10), ['abc'], 'chunk larger than string');
};

subtest 'text_substr' => sub {
    is(Template::VMethods::text_substr('hello', 1), 'ello', 'offset only');
    is(Template::VMethods::text_substr('hello', 1, 3), 'ell', 'offset + length');
    is(Template::VMethods::text_substr('hello', 1, 3, 'XY'), 'hXYo', 'with replacement');
    is(Template::VMethods::text_substr('hello', 0), 'hello', 'offset 0 (default)');
};

subtest 'text_squote' => sub {
    is(Template::VMethods::text_squote("it's"), "it\\'s", 'escapes single quotes');
    is(Template::VMethods::text_squote('back\\slash'), 'back\\\\slash', 'escapes backslashes');
    is(Template::VMethods::text_squote('hello'), 'hello', 'no change needed');
};

subtest 'text_dquote' => sub {
    is(Template::VMethods::text_dquote('say "hi"'), 'say \\"hi\\"', 'escapes double quotes');
    is(Template::VMethods::text_dquote("new\nline"), 'new\\nline', 'escapes newlines');
    is(Template::VMethods::text_dquote('back\\slash'), 'back\\\\slash', 'escapes backslashes');
    is(Template::VMethods::text_dquote('hello'), 'hello', 'no change needed');
};

#------------------------------------------------------------------------
# hash virtual methods
#------------------------------------------------------------------------

subtest 'hash_item' => sub {
    my %h = (foo => 'bar', baz => 42);
    is(Template::VMethods::hash_item(\%h, 'foo'), 'bar', 'get item');
    is(Template::VMethods::hash_item(\%h, 'baz'), 42, 'get numeric value');
    is(Template::VMethods::hash_item(\%h, 'missing'), undef, 'missing key');
    is(Template::VMethods::hash_item(\%h), undef, 'no key defaults to empty string lookup');
};

subtest 'hash_item respects PRIVATE' => sub {
    local $Template::VMethods::PRIVATE = qr/^_/;
    my %h = (_secret => 'hidden', public => 'visible');
    is(Template::VMethods::hash_item(\%h, '_secret'), undef, 'private key blocked');
    is(Template::VMethods::hash_item(\%h, 'public'), 'visible', 'public key allowed');
};

subtest 'hash_hash' => sub {
    my $h = { a => 1 };
    is(Template::VMethods::hash_hash($h), $h, 'returns self');
};

subtest 'hash_size' => sub {
    is(Template::VMethods::hash_size({ a => 1, b => 2 }), 2, 'size 2');
    is(Template::VMethods::hash_size({}), 0, 'empty hash');
};

subtest 'hash_empty' => sub {
    is(Template::VMethods::hash_empty({}), 1, 'empty hash');
    is(Template::VMethods::hash_empty({ a => 1 }), 0, 'non-empty hash');
};

subtest 'hash_each' => sub {
    my $result = Template::VMethods::hash_each({ a => 1 });
    is(ref $result, 'ARRAY', 'returns arrayref');
    is(scalar @$result, 2, 'flattened key-value pairs');
};

subtest 'hash_keys' => sub {
    my $result = Template::VMethods::hash_keys({ b => 2, a => 1 });
    is(ref $result, 'ARRAY', 'returns arrayref');
    is_deeply([sort @$result], ['a', 'b'], 'all keys present');
};

subtest 'hash_values' => sub {
    my $result = Template::VMethods::hash_values({ a => 1, b => 2 });
    is(ref $result, 'ARRAY', 'returns arrayref');
    is_deeply([sort @$result], [1, 2], 'all values present');
};

subtest 'hash_items' => sub {
    my $result = Template::VMethods::hash_items({ a => 1 });
    is(ref $result, 'ARRAY', 'returns arrayref');
    is(scalar @$result, 2, 'flattened like each');
};

subtest 'hash_pairs' => sub {
    my $result = Template::VMethods::hash_pairs({ b => 2, a => 1 });
    is(ref $result, 'ARRAY', 'returns arrayref');
    is(scalar @$result, 2, 'one entry per key');
    is($result->[0]{key}, 'a', 'sorted by key: first');
    is($result->[0]{value}, 1, 'value for a');
    is($result->[1]{key}, 'b', 'sorted by key: second');
    is($result->[1]{value}, 2, 'value for b');
};

subtest 'hash_list' => sub {
    my %h = (b => 2, a => 1);

    my $pairs = Template::VMethods::hash_list(\%h);
    is(ref $pairs, 'ARRAY', 'default returns pairs');
    is($pairs->[0]{key}, 'a', 'sorted pairs');

    my $keys = Template::VMethods::hash_list(\%h, 'keys');
    is_deeply([sort @$keys], ['a', 'b'], 'keys mode');

    my $vals = Template::VMethods::hash_list(\%h, 'values');
    is_deeply([sort @$vals], [1, 2], 'values mode');

    my $each = Template::VMethods::hash_list(\%h, 'each');
    is(ref $each, 'ARRAY', 'each mode returns arrayref');
    is(scalar @$each, 4, 'each mode flattens');
};

subtest 'hash_exists' => sub {
    my %h = (a => 1, b => undef);
    ok(Template::VMethods::hash_exists(\%h, 'a'), 'key exists');
    ok(Template::VMethods::hash_exists(\%h, 'b'), 'key exists even if undef');
    ok(!Template::VMethods::hash_exists(\%h, 'c'), 'key does not exist');
};

subtest 'hash_defined' => sub {
    my %h = (a => 1, b => undef);
    is(Template::VMethods::hash_defined(\%h), 1, 'no arg returns 1');
    is(Template::VMethods::hash_defined(\%h, 'a'), 1, 'defined value');
    is(Template::VMethods::hash_defined(\%h, 'b'), '', 'undef value');
    is(Template::VMethods::hash_defined(\%h, 'c'), '', 'missing key');
};

subtest 'hash_delete' => sub {
    my %h = (a => 1, b => 2, c => 3);
    Template::VMethods::hash_delete(\%h, 'a', 'c');
    is_deeply(\%h, { b => 2 }, 'deletes multiple keys');
};

subtest 'hash_import' => sub {
    my %h = (a => 1);
    my $result = Template::VMethods::hash_import(\%h, { b => 2, c => 3 });
    is($result, '', 'returns empty string');
    is_deeply(\%h, { a => 1, b => 2, c => 3 }, 'imported keys');

    my %h2 = (a => 1);
    Template::VMethods::hash_import(\%h2, 'not a hash');
    is_deeply(\%h2, { a => 1 }, 'non-hash import is no-op');
};

subtest 'hash_sort' => sub {
    my %h = (x => 'cherry', y => 'apple', z => 'banana');
    my $result = Template::VMethods::hash_sort(\%h);
    is_deeply($result, ['y', 'z', 'x'], 'keys sorted by value (case insensitive)');
};

subtest 'hash_nsort' => sub {
    my %h = (x => 30, y => 10, z => 20);
    my $result = Template::VMethods::hash_nsort(\%h);
    is_deeply($result, ['y', 'z', 'x'], 'keys sorted numerically by value');
};

#------------------------------------------------------------------------
# list virtual methods
#------------------------------------------------------------------------

subtest 'list_item' => sub {
    my @list = ('a', 'b', 'c');
    is(Template::VMethods::list_item(\@list, 0), 'a', 'item 0');
    is(Template::VMethods::list_item(\@list, 1), 'b', 'item 1');
    is(Template::VMethods::list_item(\@list, 2), 'c', 'item 2');
    is(Template::VMethods::list_item(\@list), 'a', 'default index 0');
};

subtest 'list_list' => sub {
    my $list = [1, 2, 3];
    is(Template::VMethods::list_list($list), $list, 'returns self');
};

subtest 'list_hash' => sub {
    my $result = Template::VMethods::list_hash(['a', 1, 'b', 2]);
    is_deeply($result, { a => 1, b => 2 }, 'pairs to hash');

    $result = Template::VMethods::list_hash(['x', 'y', 'z'], 0);
    is_deeply($result, { 0 => 'x', 1 => 'y', 2 => 'z' }, 'numbered keys starting at 0');

    $result = Template::VMethods::list_hash(['x', 'y'], 10);
    is_deeply($result, { 10 => 'x', 11 => 'y' }, 'numbered keys starting at 10');
};

subtest 'list_push' => sub {
    my @list = (1, 2);
    my $result = Template::VMethods::list_push(\@list, 3, 4);
    is($result, '', 'returns empty string');
    is_deeply(\@list, [1, 2, 3, 4], 'items pushed');
};

subtest 'list_pop' => sub {
    my @list = (1, 2, 3);
    my $result = Template::VMethods::list_pop(\@list);
    is($result, 3, 'returns popped item');
    is_deeply(\@list, [1, 2], 'list shortened');
};

subtest 'list_unshift' => sub {
    my @list = (3, 4);
    my $result = Template::VMethods::list_unshift(\@list, 1, 2);
    is($result, '', 'returns empty string');
    is_deeply(\@list, [1, 2, 3, 4], 'items unshifted');
};

subtest 'list_shift' => sub {
    my @list = (1, 2, 3);
    my $result = Template::VMethods::list_shift(\@list);
    is($result, 1, 'returns shifted item');
    is_deeply(\@list, [2, 3], 'list shortened');
};

subtest 'list_max' => sub {
    is(Template::VMethods::list_max([1, 2, 3]), 2, 'max index');
    is(Template::VMethods::list_max([42]), 0, 'single item');
    is(Template::VMethods::list_max([]), -1, 'empty list');
};

subtest 'list_size' => sub {
    is(Template::VMethods::list_size([1, 2, 3]), 3, 'size 3');
    is(Template::VMethods::list_size([42]), 1, 'single item');
    is(Template::VMethods::list_size([]), 0, 'empty list');
};

subtest 'list_empty' => sub {
    is(Template::VMethods::list_empty([]), 1, 'empty list');
    is(Template::VMethods::list_empty([1]), 0, 'non-empty list');
};

subtest 'list_defined' => sub {
    my @list = (1, undef, 3);
    is(Template::VMethods::list_defined(\@list), 1, 'no arg: list is defined');
    is(Template::VMethods::list_defined(\@list, 0), 1, 'index 0 defined');
    is(Template::VMethods::list_defined(\@list, 1), '', 'index 1 undef');
    is(Template::VMethods::list_defined(\@list, 2), 1, 'index 2 defined');
    is(Template::VMethods::list_defined(\@list, 'bah'), undef, 'non-numeric index');
};

subtest 'list_first' => sub {
    my @list = (10, 20, 30, 40, 50);
    is(Template::VMethods::list_first(\@list), 10, 'first element');
    is_deeply(Template::VMethods::list_first(\@list, 3), [10, 20, 30], 'first 3');
    is_deeply(Template::VMethods::list_first(\@list, 1), [10], 'first 1');
};

subtest 'list_last' => sub {
    my @list = (10, 20, 30, 40, 50);
    is(Template::VMethods::list_last(\@list), 50, 'last element');
    is_deeply(Template::VMethods::list_last(\@list, 3), [30, 40, 50], 'last 3');
    is_deeply(Template::VMethods::list_last(\@list, 1), [50], 'last 1');
};

subtest 'list_reverse' => sub {
    is_deeply(Template::VMethods::list_reverse([1, 2, 3]), [3, 2, 1], 'reverses');
    is_deeply(Template::VMethods::list_reverse([42]), [42], 'single item');
    is_deeply(Template::VMethods::list_reverse([]), [], 'empty list');

    my @orig = (1, 2, 3);
    Template::VMethods::list_reverse(\@orig);
    is_deeply(\@orig, [1, 2, 3], 'does not mutate original');
};

subtest 'list_grep' => sub {
    my @list = ('apple', 'banana', 'apricot', 'cherry');
    is_deeply(Template::VMethods::list_grep(\@list, '^a'), ['apple', 'apricot'], 'grep with regex');
    is_deeply(Template::VMethods::list_grep(\@list, 'xyz'), [], 'no matches');
    is_deeply(Template::VMethods::list_grep(\@list), ['apple', 'banana', 'apricot', 'cherry'],
        'undef pattern matches all');
};

subtest 'list_join' => sub {
    is(Template::VMethods::list_join([1, 2, 3], ', '), '1, 2, 3', 'join with comma');
    is(Template::VMethods::list_join([1, 2, 3]), '1 2 3', 'default join with space');
    is(Template::VMethods::list_join([1, undef, 3], '-'), '1--3', 'undef becomes empty');
    is(Template::VMethods::list_join([42]), '42', 'single item');
};

subtest 'list_sort' => sub {
    is_deeply(Template::VMethods::list_sort(['Banana', 'apple', 'Cherry']),
        ['apple', 'Banana', 'Cherry'], 'case-insensitive sort');

    is_deeply(Template::VMethods::list_sort(['a']), ['a'], 'single item unchanged');
    is_deeply(Template::VMethods::list_sort([]), [], 'empty list unchanged');
};

subtest 'list_sort with fields' => sub {
    my @list = (
        { name => 'Zelda', age => 25 },
        { name => 'alice', age => 30 },
        { name => 'Bob',   age => 20 },
    );
    my $result = Template::VMethods::list_sort(\@list, 'name');
    is($result->[0]{name}, 'alice', 'sorted by name field (case insensitive)');
    is($result->[1]{name}, 'Bob', 'Bob second');
    is($result->[2]{name}, 'Zelda', 'Zelda last');
};

subtest 'list_sort with blessed objects' => sub {
    {
        package MockSortable;
        sub new { bless { name => $_[1] }, $_[0] }
        sub name { $_[0]->{name} }
    }
    my @list = (
        MockSortable->new('cherry'),
        MockSortable->new('apple'),
        MockSortable->new('banana'),
    );
    my $result = Template::VMethods::list_sort(\@list, 'name');
    is($result->[0]->name, 'apple', 'sorted objects by method');
    is($result->[1]->name, 'banana', 'banana second');
    is($result->[2]->name, 'cherry', 'cherry third');
};

subtest 'list_nsort' => sub {
    is_deeply(Template::VMethods::list_nsort([30, 10, 20]),
        [10, 20, 30], 'numeric sort');
    is_deeply(Template::VMethods::list_nsort([5]), [5], 'single item');
    is_deeply(Template::VMethods::list_nsort([]), [], 'empty list');
};

subtest 'list_nsort with fields' => sub {
    my @list = (
        { name => 'c', val => 30 },
        { name => 'a', val => 10 },
        { name => 'b', val => 20 },
    );
    my $result = Template::VMethods::list_nsort(\@list, 'val');
    is($result->[0]{name}, 'a', 'sorted by numeric field');
    is($result->[1]{name}, 'b', 'b second');
    is($result->[2]{name}, 'c', 'c third');
};

subtest 'list_unique' => sub {
    is_deeply(Template::VMethods::list_unique([1, 2, 3, 2, 1, 4]),
        [1, 2, 3, 4], 'removes duplicates preserving order');
    is_deeply(Template::VMethods::list_unique([1]), [1], 'single item');
    is_deeply(Template::VMethods::list_unique([]), [], 'empty list');
};

subtest 'list_import' => sub {
    my @list = (1, 2);
    my $result = Template::VMethods::list_import(\@list, [3, 4], [5]);
    is($result, \@list, 'returns same list ref');
    is_deeply(\@list, [1, 2, 3, 4, 5], 'imported arrays');

    my @list2 = (1);
    Template::VMethods::list_import(\@list2, 'not_array');
    is_deeply(\@list2, [1], 'non-array args ignored');
};

subtest 'list_merge' => sub {
    my @list = (1, 2);
    my $result = Template::VMethods::list_merge(\@list, [3, 4], [5]);
    is_deeply($result, [1, 2, 3, 4, 5], 'merged into new list');
    is_deeply(\@list, [1, 2], 'original unchanged');

    $result = Template::VMethods::list_merge(\@list, 'not_array');
    is_deeply($result, [1, 2], 'non-array args ignored');
};

subtest 'list_slice' => sub {
    my @list = (10, 20, 30, 40, 50);
    is_deeply(Template::VMethods::list_slice(\@list, 1, 3), [20, 30, 40], 'slice 1..3');
    is_deeply(Template::VMethods::list_slice(\@list, 0, 0), [10], 'single element');
    is_deeply(Template::VMethods::list_slice(\@list), [10, 20, 30, 40, 50], 'default: entire list');
    is_deeply(Template::VMethods::list_slice(\@list, -2), [40, 50], 'negative from');
    is_deeply(Template::VMethods::list_slice(\@list, 0, -1), [10, 20, 30, 40, 50], 'negative to');
};

subtest 'list_splice' => sub {
    my @list = (1, 2, 3, 4, 5);
    my $removed = Template::VMethods::list_splice(\@list, 1, 2);
    is_deeply($removed, [2, 3], 'returns removed items');
    is_deeply(\@list, [1, 4, 5], 'list modified');

    @list = (1, 2, 3, 4, 5);
    $removed = Template::VMethods::list_splice(\@list, 1, 2, ['a', 'b']);
    is_deeply($removed, [2, 3], 'returns removed on replace');
    is_deeply(\@list, [1, 'a', 'b', 4, 5], 'replacement inserted');

    @list = (1, 2, 3);
    $removed = Template::VMethods::list_splice(\@list, 1);
    is_deeply($removed, [2, 3], 'offset only');
    is_deeply(\@list, [1], 'list truncated');

    @list = (1, 2, 3);
    $removed = Template::VMethods::list_splice(\@list);
    is_deeply($removed, [1, 2, 3], 'no args: empties list');
    is_deeply(\@list, [], 'list is empty');

    @list = (1, 2, 3);
    $removed = Template::VMethods::list_splice(\@list, 1, 1, 'x', 'y');
    is_deeply($removed, [2], 'multiple replace args');
    is_deeply(\@list, [1, 'x', 'y', 3], 'multiple replacements inserted');
};

#------------------------------------------------------------------------
# exported table structure
#------------------------------------------------------------------------

subtest 'vmethod tables are populated' => sub {
    is(ref $Template::VMethods::ROOT_VMETHODS, 'HASH', 'ROOT_VMETHODS is hash');
    is(ref $Template::VMethods::TEXT_VMETHODS, 'HASH', 'TEXT_VMETHODS is hash');
    is(ref $Template::VMethods::HASH_VMETHODS, 'HASH', 'HASH_VMETHODS is hash');
    is(ref $Template::VMethods::LIST_VMETHODS, 'HASH', 'LIST_VMETHODS is hash');

    ok(exists $Template::VMethods::ROOT_VMETHODS->{inc}, 'ROOT has inc');
    ok(exists $Template::VMethods::ROOT_VMETHODS->{dec}, 'ROOT has dec');
    ok(exists $Template::VMethods::TEXT_VMETHODS->{upper}, 'TEXT has upper');
    ok(exists $Template::VMethods::TEXT_VMETHODS->{html}, 'TEXT has html');
    ok(exists $Template::VMethods::TEXT_VMETHODS->{xml}, 'TEXT has xml');
    ok(exists $Template::VMethods::HASH_VMETHODS->{keys}, 'HASH has keys');
    ok(exists $Template::VMethods::LIST_VMETHODS->{sort}, 'LIST has sort');
};

subtest 'html and xml are from Filters' => sub {
    is($Template::VMethods::TEXT_VMETHODS->{html},
        \&Template::Filters::html_filter, 'html points to Filters');
    is($Template::VMethods::TEXT_VMETHODS->{xml},
        \&Template::Filters::xml_filter, 'xml points to Filters');
};

done_testing();
