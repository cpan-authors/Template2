#==============================================================================
# 
# Template::Plugin::Dumper
#
# DESCRIPTION
#
# A Template Plugin to provide a Template Interface to Data::Dumper
#
# AUTHOR
#   Simon Matthews <sam@tt2.org>
#
# COPYRIGHT
#   Copyright (C) 2000 Simon Matthews.  All Rights Reserved
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#==============================================================================

package Template::Plugin::Dumper;

use strict;
use warnings;
use base 'Template::Plugin';
use Data::Dumper;

our $VERSION = '3.100';
our $DEBUG   = 0 unless defined $DEBUG;
our @DUMPER_ARGS = qw( Indent Pad Varname Purity Useqq Terse Freezer
                       Toaster Deepcopy Quotekeys Bless Maxdepth Sortkeys );
our $AUTOLOAD;

#==============================================================================
#                      -----  CLASS METHODS -----
#==============================================================================

#------------------------------------------------------------------------
# new($context, \@params)
#------------------------------------------------------------------------

sub new {
    my ($class, $context, $params) = @_;

    bless { 
        _CONTEXT => $context, 
        params   => $params || {},
    }, $class;
}

sub get_dump_obj {
    my $self = shift;

    my $dumper_obj = Data::Dumper->new( \@_ );

    my $params = $self->{ params };

    foreach my $arg ( @DUMPER_ARGS ) {
        my $val = exists $params->{ lc $arg } ? $params->{ lc $arg }
                :                               $params->{    $arg };

        $dumper_obj->$arg( $val ) if defined $val;
    }

    return $dumper_obj;
}

sub dump { scalar shift->get_dump_obj( @_ )->Dump() }

sub dump_html {
    my $self = shift;

    my $content = $self->dump( @_ );

    for ($content) {
        s/&/&amp;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
        s/"/&quot;/g;
        s/'/&#39;/g;
        s/\n/<br>\n/g;
    }

    return $content;
}

1;

__END__

=head1 NAME

Template::Plugin::Dumper - Plugin interface to Data::Dumper

=head1 SYNOPSIS

    [% USE Dumper %]
    
    [% Dumper.dump(variable) %]
    [% Dumper.dump_html(variable) %]

=head1 DESCRIPTION

This is a very simple Template Toolkit Plugin Interface to the L<Data::Dumper>
module.  A C<Dumper> object will be instantiated via the following directive:

    [% USE Dumper %]

As a standard plugin, you can also specify its name in lower case:

    [% USE dumper %]

The following L<Data::Dumper> options are supported as constructor arguments
to affect the output generated:

C<Indent>, C<Pad>, C<Varname>, C<Purity>, C<Useqq>, C<Terse>, C<Freezer>,
C<Toaster>, C<Deepcopy>, C<Quotekeys>, C<Bless>, C<Maxdepth>, C<Sortkeys>.

See L<Data::Dumper> for further details on each option.

    [% USE dumper(Indent=0, Pad="<br>") %]
    [% USE dumper(Sortkeys=1, Terse=1) %]

These options can also be specified in lower case.

    [% USE dumper(indent=0, pad="<br>") %]

=head1 METHODS

There are two methods supported by the C<Dumper> object.  Each will
output into the template the contents of the variables passed to the
object method.

=head2 dump()

Generates a raw text dump of the data structure(s) passed

    [% USE Dumper %]
    [% Dumper.dump(myvar) %]
    [% Dumper.dump(myvar, yourvar) %]

=head2 dump_html()

Generates a dump of the data structures, as per L<dump()>, but with the 
characters E<lt>, E<gt> and E<amp> converted to their equivalent HTML
entities and newlines converted to E<lt>brE<gt>.

    [% USE Dumper %]
    [% Dumper.dump_html(myvar) %]

=head1 AUTHOR

Simon Matthews E<lt>sam@tt2.orgE<gt>

=head1 COPYRIGHT

Copyright (C) 2000 Simon Matthews.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin>, L<Data::Dumper>

