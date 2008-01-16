package
    DBIx::Class::CDBICompat::ColumnsAsHash;

use strict;
use warnings;

use Scalar::Defer;
use Scalar::Util qw(weaken);
use Carp;


=head1 NAME

DBIx::Class::CDBICompat::ColumnsAsHash

=head1 SYNOPSIS

See DBIx::Class::CDBICompat for directions for use.

=head1 DESCRIPTION

Emulates the I<undocumnted> behavior of Class::DBI where the object can be accessed as a hash of columns.  This is often used as a performance hack.

    my $column = $row->{column};

=head2 Differences from Class::DBI

This will warn when a column is accessed as a hash key.

=cut

sub new {
    my $class = shift;

    my $new = $class->next::method(@_);

    $new->_make_columns_as_hash;

    return $new;
}

sub inflate_result {
    my $class = shift;

    my $new = $class->next::method(@_);
    
    $new->_make_columns_as_hash;
    
    return $new;
}


sub _make_columns_as_hash {
    my $self = shift;
    
    weaken $self;
    for my $col ($self->columns) {
        if( exists $self->{$col} ) {
            warn "Skipping mapping $col to a hash key because it exists";
        }

        next unless $self->can($col);
        $self->{$col} = defer {
            my $class = ref $self;
            carp "Column '$col' of '$class/$self' was accessed as a hash";
            $self->$col();
        };
    }
}

sub update {
    my $self = shift;
    
    for my $col ($self->columns) {
        if( $self->_hash_changed($col) ) {
            my $class = ref $self;
            carp "Column '$col' of '$class/$self' was updated as a hash";
            $self->$col($self->_get_column_from_hash($col));
            $self->{$col} = defer { $self->$col() };
        }
    }
    
    return $self->next::method(@_);
}

sub _hash_changed {
    my($self, $col) = @_;
    
    return 0 unless exists $self->{$col};
    
    my $hash = $self->_get_column_from_hash($col);
    my $obj  = $self->$col();

    return 1 if defined $hash xor defined $obj;
    return 0 if !defined $hash and !defined $obj;
    return 1 if $hash ne $obj;
    return 0;
}

# get the column value without a warning
sub _get_column_from_hash {
    my($self, $col) = @_;
    
    local $SIG{__WARN__} = sub {};
    return force $self->{$col};
}

1;
