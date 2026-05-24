#============================================================= -*-Perl-*-
#
# Template::Map
#
# DESCRIPTION
#   This module implements a generic name to template mapping service.  It
#   replaces part of the functionality of the experimental Template::View
#   module.
#
# NOTE
#   This is a work-in-progress.  It is not part of the standard TT
#   distribution and may never be.
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
# COPYRIGHT
#   Copyright (C) 2022 Andy Wardley.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#============================================================================

package Template::Map;

use strict;
use warnings;
use base 'Template::Base';

our $VERSION  = '3.105';
our $DEBUG    = 0 unless defined $DEBUG;
our $MAP = {
    HASH    => 'hash',
    ARRAY   => 'list',
    TEXT    => 'text',
    default => '',
};
our $METHOD = 'TT_name';

#$DEBUG = 1;

#------------------------------------------------------------------------
# _init(\%config)
#
# Initialisation method called by the Template::Base class new()
# constructor.
#------------------------------------------------------------------------

sub _init {
    my ($self, $config) = @_;

    foreach my $arg (qw( prefix suffix default )) {
	$self->{ $arg } = $config->{ $arg } || '';
    }

    my $format = $config->{ format } || [ ];
    $format = [ $format ] unless ref $format eq 'ARRAY';
    $self->{ format } = $format;

    my $map = $config->{ map } || { };
    $self->{ map } = { %$MAP, %$map };

    return $self;
}


sub map {
    my ($self, $item) = @_;
    return $self->names( $self->name($item) );
}


sub names {
    my ($self, $name) = @_;
    my (@names);

    # apply each format
    foreach my $format (@{ $self->{ format } }) {
	push(@names, sprintf($format, $name));
    }

    # also add the name with optional prefix/suffix added
    push(@names, "$self->{ prefix }$name$self->{ suffix }")
        unless @names;

    # finally add any default option
    push(@names, $self->{ default }) if $self->{ default };

    return \@names;
}


sub name {
    my ($self, $item) = @_;
    my $map    = $self->{ map } || $MAP;
    my $type   = ref $item || return $map->{ TEXT };
    my $method = $METHOD;
    my $name;

    return $map->{ $type }
        if defined $map->{ $type };

    if ( UNIVERSAL::can($item, $method) ) {
	$self->DEBUG("Calling \$item->$method\n") if $DEBUG;
	$name = $item->$method();
    }
    else {
	($name = $type) =~ s/\W+/_/g;
    }

    return $name;
}


1;

