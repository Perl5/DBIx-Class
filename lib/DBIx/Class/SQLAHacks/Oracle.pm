package # Hide from PAUSE
  DBIx::Class::SQLAHacks::Oracle;

use warnings;
use strict;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

# 
#  TODO:
#   - Review by experienced DBIC/SQL:A developers :-)
#   - Problem with count and connect_by look the TODO in t/73oracle.t
# 

sub new {
  my $self = shift;
  my %opts = (ref $_[0] eq 'HASH') ? %{$_[0]} : @_;
  push @{$opts{special_ops}}, {
    regex => qr/^prior$/i,
    handler => '_where_field_PRIOR',
  };

  $self->SUPER::new (\%opts);
}

sub select {
    my ($self, $table, $fields, $where, $rs_attrs, @rest) = @_;

    my ($sql, @bind) = $self->SUPER::select($table, $fields, $where, $rs_attrs, @rest);
    push @bind, @{$self->{_oracle_connect_by_binds}};

    return wantarray ? ($sql, @bind) : $sql;
}

sub _emulate_limit {
    my ( $self, $syntax, $sql, $rs_attrs, $rows, $offset ) = @_;

    my ($cb_sql, @cb_bind) = $self->_connect_by($rs_attrs);
    $sql .= $cb_sql;
    $self->{_oracle_connect_by_binds} = \@cb_bind;

    return $self->SUPER::_emulate_limit($syntax, $sql, $rs_attrs, $rows, $offset);
}

sub _connect_by {
    my ($self, $attrs) = @_;

    my $sql = '';
    my @bind;

    if ( ref($attrs) eq 'HASH' ) {
        if ( $attrs->{'start_with'} ) {
            my ($ws, @wb) = $self->_recurse_where( $attrs->{'start_with'} );
            $sql .= $self->_sqlcase(' start with ') . $ws;
            push @bind, @wb;
        }
        if ( my $connect_by = $attrs->{'connect_by'} ) {
            my ($connect_by_sql, @connect_by_sql_bind) = $self->_recurse_where( $attrs->{'connect_by'} );
            $sql .= sprintf(" %s %s",
                ( $attrs->{'connect_by_nocycle'} ) ? $self->_sqlcase('connect by nocycle')
                    : $self->_sqlcase('connect by'),
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
    my ( $self, $arg ) = @_;

    my ( @sql, @bind );
    for my $c ( $self->_order_by_chunks($arg) ) {
        $self->_SWITCH_refkind(
            $c,
            {
                SCALAR   => sub { push @sql, $c },
                ARRAYREF => sub { push @sql, shift @$c; push @bind, @$c },
            }
        );
    }

    my $sql =
      @sql
      ? sprintf( '%s %s', $self->_sqlcase(' order siblings by'), join( ', ', @sql ) )
      : '';

    return wantarray ? ( $sql, @bind ) : $sql;
}

# we need to add a '=' only when PRIOR is used against a column diretly
# i.e. when it is invoked by a special_op callback
sub _where_field_PRIOR {
  my ($self, $lhs, $op, $rhs) = @_;
  my ($sql, @bind) = $self->_recurse_where ($rhs);

  $sql = sprintf ('%s = %s %s ',
    $self->_convert($self->_quote($lhs)),
    $self->_sqlcase ($op),
    $sql
  );

  return ($sql, @bind);
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
