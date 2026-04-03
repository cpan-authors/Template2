#============================================================= -*-perl-*-
#
# t/zz-error-exception-gh-373.t
#
# Test that exceptions generated in the template are correctly reported as an
# error (if a Error::TypeTiny::Assertion exception is thrown this can undefine
# $@ when it is used)
#
# Written by Andy Beverley <andy@andybev.com>
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
# $Id$
#
#========================================================================

use strict;
use lib qw( ../lib );
use Template::Test;
$^W = 1;

# For these tests we don't use Type::Tiny to avoid adding a dependency, instead
# we simulate its behavior

{
    package MyException;

    # Both bool and string contexts are used when an exception is processed
    # with TT
    use overload
        bool => sub { 1 },
        '""'  => sub {
            my $self = shift;
            # Simulate stringification in Error::TypeTiny::Assertion /
            # Type::Tiny
            my $b = do {
                    local $@;
                    require B::Deparse;
                    "B::Deparse"->new;
            };
            my $code = $b->coderef2text( sub {} );
            $self->{this_error};
        };

    sub new {
        bless {
            this_error => "A horrible error",
        }, "MyException";
    }
}

# A package which dies with a MyException error
{
    package Foo;

    sub new {
        bless {}, "Foo";
    }

    sub bork { die MyException->new }
}

# A template which causes Foo to die when it is processed
my $template = Template->new({
    BLOCKS => {
        exception => "[% foo.bork %]",
    },
});

ok( ! $template->process('exception', { foo => Foo->new } ) );
my $error = $template->error();
ok( $error );
ok( ref $error eq 'Template::Exception' );
ok( $error->info."" eq 'A horrible error' );
