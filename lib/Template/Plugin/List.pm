#============================================================= -*-Perl-*-
#
# Template::Plugin::List
#
# DESCRIPTION
#   Template Toolkit plugin to implement an OO List object.
#   (work in progress)
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
# COPYRIGHT
#   Copyright (C) 2001-2022 Andy Wardley.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#============================================================================

package Template::Plugin::List;

use strict;
use warnings;
use base 'Template::Plugin';
use Template::Exception;
use overload
    q|""| => "text",
    fallback => 1;

our $VERSION = '3.100';
our $ERROR   = '';


local $" = ', ';

#------------------------------------------------------------------------

sub new {
    my ($class, @args) = @_;
    my $context = ref $class ? undef : CORE::shift(@args);
    my $config = @args && ref $args[-1] eq 'HASH' ? CORE::pop(@args) : { };

    $class = ref($class) || $class;

    my $list = defined $config->{ list }
        ? $config->{ list }
        : (scalar @args == 1 && ref $args[0] eq 'ARRAY'
            ? CORE::shift(@args)
            : [ @args ]
        );

    my $joint =
        defined $config->{ joint }
        ? $config->{ joint }
        : $config->{ join }
            ? $config->{ join }
            : ', ';

    bless {
        list  => $list,
        joint => $joint,
        _CONTEXT => $context,
    }, $class;
}


sub list {
    return $_[0]->{ list };
}


sub item {
    $_[0]->{ list }->[ $_[1] || 0 ];
}


sub hash {                              ### not sure about this one ###
    my $self = shift;
    my $n = 0;
    return { map { ($n++, $_) } @{ $self->{ list } } };
}


sub text {
    my $self = CORE::shift;
    return CORE::join($self->{ joint }, @{ $self->{ list } });
}


sub copy {
    my $self = CORE::shift;
    $self->new([ @{ $self->{ list } } ]);
}


sub throw {
    my $self = CORE::shift;
    die (Template::Exception->new('List', CORE::join('', @_)));
}


#------------------------------------------------------------------------

sub push {
    my $self = CORE::shift;
    CORE::push(@{ $self->{ list } }, @_);
    return $self;
}


sub unshift {
    my $self = CORE::shift;
    CORE::unshift(@{ $self->{ list } }, @_);
    return $self;
}


sub pop {
    my $self = CORE::shift;
    CORE::pop(@{ $self->{ list } });
    return $self;
}


sub shift {
    my $self = CORE::shift;
    CORE::shift(@{ $self->{ list } });
    return $self;
}


sub max {
    local $^W = 0;
    my $list = $_[0]->{ list };
    return $#$list;
}


sub size {
    local $^W = 0;
    my $list = $_[0]->{ list };
    return $#$list + 1;
}


1;

__END__


