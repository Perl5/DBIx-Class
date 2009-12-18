package # Hide from PAUSE
  DBIx::Class::SQLAHacks::Oracle;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

# 
#  TODO:
#   - Problems with such statements: parentid != PRIOR artistid
#   - Check the parameter syntax of connect_by
#   - Review review by experienced DBIC/SQL:A developers :-)
# 

sub new {
  my $self = shift->SUPER::new(@_);

  push @{ $self->{unary_ops} },{
      regex   => qr/^prior$/,
      handler => '_prior_as_unary_op',
  };

  push @{ $self->{special_ops} },{
      regex   => qr/^prior$/,
      handler => '_prior_as_special_op',
  };

  return $self;
}


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
            my ($connect_by_sql, @connect_by_sql_bind) = $self->_recurse_where( $attrs->{'connect_by'} );
            $sql .= sprintf(" %s %s",
                $self->_sqlcase('connect by'),
                $connect_by_sql,
            );
            push @bind, @connect_by_sql_bind;
            # $sql .= $self->_sqlcase(' connect by');
            #             foreach my $key ( keys %$connect_by ) {
            #                 $sql .= " $key = " . $connect_by->{$key};
            #             }
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

sub _prior_as_special_op {
    my ( $self, $field, $op, $arg ) = @_;

    my ( $label, $and, $placeholder );
    $label       = $self->_convert( $self->_quote($field) );
    $and         = ' ' . $self->_sqlcase('and') . ' ';
    $placeholder = $self->_convert('?');

    # TODO: $op is prior, and not the operator
    $op          = $self->_sqlcase('=');

    my ( $sql, @bind ) = $self->_SWITCH_refkind(
        $arg,
        {
            SCALARREF => sub {
                my $sql = sprintf( "%s %s PRIOR %s", $label, $op, $$arg );
                return $sql;
            },
            SCALAR => sub {
                my $sql = sprintf( "%s %s PRIOR %s", $label, $op, $placeholder );
                return ( $sql, $arg );
            },
            HASHREF => sub {    # case { '-prior' => { '=<' => 'nwiger'} }
                                # no _convert and _quote from SCALARREF
                my ( $sql, @bind ) = $self->_where_hashpair_HASHREF( $field, $arg, $op );
                $sql = sprintf( " PRIOR %s", $sql );
                return ( $sql, @bind );
            },
            FALLBACK => sub {
                # TODO
                $self->puke(" wrong way... :/");
            },
        }
    );
    return ( $sql, @bind );
}

sub _prior_as_unary_op {
    my ( $self, $op, $arg ) = @_;

    my $placeholder = $self->_convert('?');
    my $and         = ' ' . $self->_sqlcase('and') . ' ';

    my ( $sql, @bind ) = $self->_SWITCH_refkind(
        $arg,
        {
            ARRAYREF => sub {
                $self->puke("special op 'prior' accepts an arrayref with exactly two values")
                  if @$arg != 2;

                my ( @all_sql, @all_bind );

                foreach my $val ( @{$arg} ) {
                    my ( $sql, @bind ) = $self->_SWITCH_refkind($val,
                        {
                            SCALAR => sub {
                                return ( $placeholder, ($val) );
                            },
                            SCALARREF => sub {
                                return ( $$val, () );
                            },
                        }
                    );
                    push @all_sql, $sql;
                    push @all_bind, @bind;
                }
                my $sql = sprintf("PRIOR %s ",join $self->_sqlcase('='), @all_sql);
                return ($sql,@all_bind);
            },
            FALLBACK => sub {

                # TODO
                $self->puke(" wrong way... :/ ");
            },
        }
    );
    return ( $sql, @bind );
};

1;

__END__

=pod

=head1 NAME

DBIx::Class::SQLAHacks::Oracle - adds hierarchical query support for Oracle to SQL::Abstract

=head1 DESCRIPTION

See L<DBIx::Class::Storage::DBI::Oracle::Generic> for more informations about
how to use hierarchical queries with DBIx::Class.

=cut
