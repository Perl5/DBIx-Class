package DBIx::Class::Storage::DBI::InterBase;

# partly stolen from DBIx::Class::Storage::DBI::MSSQL

use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';
use List::Util();

__PACKAGE__->mk_group_accessors(simple => qw/
  _fb_auto_incs
/);

sub _prep_for_execute {
  my $self = shift;
  my ($op, $extra_bind, $ident, $args) = @_;

  my ($sql, $bind) = $self->next::method (@_);

  if ($op eq 'insert') {
    my @auto_inc_cols = grep {
      my $inserting = $args->[0]{$_};

      $ident->column_info($_)->{is_auto_increment} && (
        (not defined $inserting)
        ||
        (ref $inserting eq 'SCALAR' && $$inserting eq 'NULL')
      )
    } $ident->columns;

    if (@auto_inc_cols) {
      my $auto_inc_cols =
        join ', ',
        map $self->_quote_column_for_returning($_), @auto_inc_cols;

      $sql .= " RETURNING ($auto_inc_cols)";

      $self->_fb_auto_incs([]);
      $self->_fb_auto_incs->[0] = \@auto_inc_cols;
    }
  }

  return ($sql, $bind);
}

sub _quote_column_for_returning {
  my ($self, $col) = @_;

  return $self->sql_maker->_quote($col);
}

sub _execute {
  my $self = shift;
  my ($op) = @_;

  my ($rv, $sth, @bind) = $self->dbh_do($self->can('_dbh_execute'), @_);

  if ($op eq 'insert' && $self->_fb_auto_incs) {
    local $@;
    my (@auto_incs) = eval {
      local $SIG{__WARN__} = sub {};
      $sth->fetchrow_array
    };
    $self->_fb_auto_incs->[1] = \@auto_incs;
    $sth->finish;
  }

  return wantarray ? ($rv, $sth, @bind) : $rv;
}

sub last_insert_id {
  my ($self, $source, @cols) = @_;
  my @result;

  my %auto_incs;
  @auto_incs{ @{ $self->_fb_auto_incs->[0] } } =
    @{ $self->_fb_auto_incs->[1] };

  push @result, $auto_incs{$_} for @cols;

  return @result;
}

# this sub stolen from DB2

sub _sql_maker_opts {
  my ( $self, $opts ) = @_;

  if ( $opts ) {
    $self->{_sql_maker_opts} = { %$opts };
  }

  return { limit_dialect => 'FirstSkip', %{$self->{_sql_maker_opts}||{}} };
}

sub datetime_parser_type { __PACKAGE__ }

my ($datetime_parser, $datetime_formatter);

sub parse_datetime {
    shift;
    require DateTime::Format::Strptime;
    $datetime_parser ||= DateTime::Format::Strptime->new(
        pattern => '%a %d %b %Y %r',
# there should be a %Z (TZ) on the end, but it's ambiguous and not parsed
        on_error => 'croak',
    );
    $datetime_parser->parse_datetime(shift);
}

sub format_datetime {
    shift;
    require DateTime::Format::Strptime;
    $datetime_formatter ||= DateTime::Format::Strptime->new(
        pattern => '%F %H:%M:%S.%4N',
        on_error => 'croak',
    );
    $datetime_formatter->format_datetime(shift);
}

1;
