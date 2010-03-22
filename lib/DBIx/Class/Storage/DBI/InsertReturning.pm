package DBIx::Class::Storage::DBI::InsertReturning;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

=head1 NAME

DBIx::Class::Storage::DBI::InsertReturning - Storage component for RDBMSes
supporting INSERT ... RETURNING

=head1 DESCRIPTION

Provides Auto-PK and
L<is_auto_increment|DBIx::Class::ResultSource/is_auto_increment> support for
databases supporting the C<INSERT ... RETURNING> syntax.

=cut

sub insert {
  my $self = shift;
  my ($source, $to_insert, $opts) = @_;

  return $self->next::method (@_) unless ($opts && $opts->{returning});

  my $updated_cols = $self->_prefetch_insert_auto_nextvals ($source, $to_insert);

  my $bind_attributes = $self->source_bind_attributes($source);
  my ($rv, $sth) = $self->_execute (insert => [], $source, $bind_attributes, $to_insert, $opts);

  if (my @ret_cols = @{$opts->{returning}}) {

    my @ret_vals = eval {
      local $SIG{__WARN__} = sub {};
      my @r = $sth->fetchrow_array;
      $sth->finish;
      @r;
    };

    my %ret;
    @ret{@ret_cols} = @ret_vals if (@ret_vals);

    $updated_cols = {
      %$updated_cols,
      %ret,
    };
  }

  return $updated_cols;
}

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
