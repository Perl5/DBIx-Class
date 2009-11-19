package # Hide from PAUSE
  DBIx::Class::SQLAHacks::Oracle;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

sub select {
    my ($self, $table, $fields, $where, $order, @rest) = @_;

    $self->{_db_specific_attrs} = pop @rest;

    my ($sql, @bind) = $self->SUPER::select($table, $fields, $where, $order, @rest);
    push @bind, @{$self->{_oracle_connect_by_binds}};

    return wantarray ? ($sql, @bind) : $sql;
}

sub _emulate_limit {
    my ( $self, $syntax, $sql, $order, $rows, $offset ) = @_;

    my ($cb_sql, @cb_bind) = $self->_connect_by();
    $sql .= $cb_sql;
    $self->{_oracle_connect_by_binds} = \@cb_bind;

    return $self->SUPER::_emulate_limit($syntax, $sql, $order, $rows, $offset);
}

sub _connect_by {
    my ($self) = @_;
    my $attrs = $self->{_db_specific_attrs};
    my $sql = '';
    my @bind;

    if ( ref($attrs) eq 'HASH' ) {
        if ( $attrs->{'start_with'} ) {
            my ($ws, @wb) = $self->_recurse_where( $attrs->{'start_with'} );
            $sql .= $self->_sqlcase(' start with ') . $ws;
            push @bind, @wb;
        }
        if ( my $connect_by = $attrs->{'connect_by'}) {
            $sql .= $self->_sqlcase(' connect by');
            foreach my $key ( keys %$connect_by ) {
                $sql .= " $key = " . $connect_by->{$key};
            }
        }
        if ( $attrs->{'order_siblings_by'} ) {
            $sql .= $self->_order_siblings_by( $attrs->{'order_siblings_by'} );
        }
    }

    return wantarray ? ($sql, @bind) : $sql;
}

sub _order_siblings_by {
    my $self = shift;
    my $ref = ref $_[0];

    my @vals = $ref eq 'ARRAY'  ? @{$_[0]} :
               $ref eq 'SCALAR' ? ${$_[0]} :
               $ref eq ''       ? $_[0]    :
               puke( "Unsupported data struct $ref for ORDER SIBILINGS BY" );

    my $val = join ', ', map { $self->_quote($_) } @vals;
    return $val ? $self->_sqlcase(' order siblings by')." $val" : '';
}

1;

__END__

=pod

=head1 NAME

DBIx::Class::SQLAHacks::Oracle - adds hierarchical query support for Oracle to SQL::Abstract

=head1 DESCRIPTION

See L<DBIx::Class::Storage::DBI::Oracle::Generic> for more informations about
how to use hierarchical queries with DBIx::Class.

=cut
