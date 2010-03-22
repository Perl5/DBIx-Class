package DBIx::Class::Storage::DBI::InsertReturning;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

__PACKAGE__->mk_group_accessors(simple => qw/
  _returning_cols
/);

=head1 NAME

DBIx::Class::Storage::DBI::InsertReturning - Storage component for RDBMSes
supporting INSERT ... RETURNING

=head1 DESCRIPTION

Provides Auto-PK and
L<is_auto_increment|DBIx::Class::ResultSource/is_auto_increment> support for
databases supporting the C<INSERT ... RETURNING> syntax. Currently
L<PostgreSQL|DBIx::Class::Storage::DBI::Pg> and
L<Firebird|DBIx::Class::Storage::DBI::InterBase>.

=cut

sub _prep_for_execute {
  my $self = shift;
  my ($op, $extra_bind, $ident, $args) = @_;

  if ($op eq 'insert') {
    $self->_returning_cols([]);

    my %pk;
    @pk{$ident->primary_columns} = ();

    my @auto_inc_cols = grep {
      my $inserting = $args->[0]{$_};

      ($ident->column_info($_)->{is_auto_increment}
        || exists $pk{$_})
      && (
        (not defined $inserting)
        ||
        (ref $inserting eq 'SCALAR' && $$inserting =~ /^null\z/i)
      )
    } $ident->columns;

    if (@auto_inc_cols) {
      $args->[1]{returning} = \@auto_inc_cols;

      $self->_returning_cols->[0] = \@auto_inc_cols;
    }
  }

  return $self->next::method(@_);
}

sub _execute {
  my $self = shift;
  my ($op) = @_;

  my ($rv, $sth, @bind) = $self->dbh_do($self->can('_dbh_execute'), @_);

  if ($op eq 'insert' && $self->_returning_cols) {
    local $@;
    my (@returning_cols) = eval {
      local $SIG{__WARN__} = sub {};
      $sth->fetchrow_array
    };
    $self->_returning_cols->[1] = \@returning_cols;
    $sth->finish;
  }

  return wantarray ? ($rv, $sth, @bind) : $rv;
}

sub insert {
  my $self = shift;

  my $updated_cols = $self->next::method(@_);

  if ($self->_returning_cols->[0]) {
    my %returning_cols;
    @returning_cols{ @{ $self->_returning_cols->[0] } } = @{ $self->_returning_cols->[1] };

    $updated_cols = { %$updated_cols, %returning_cols };
  }

  return $updated_cols;
}

sub last_insert_id {
  my ($self, $source, @cols) = @_;
  my @result;

  my %returning_cols;
  @returning_cols{ @{ $self->_returning_cols->[0] } } =
    @{ $self->_returning_cols->[1] };

  push @result, $returning_cols{$_} for @cols;

  return @result;
}

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
