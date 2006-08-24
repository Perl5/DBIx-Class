package DBIx::Class::Storage::DBI::NoBindVars;

use strict;
use warnings;

use base 'DBIx::Class::Storage::DBI';

=head1 NAME 

DBIx::Class::Storage::DBI::NoBindVars - Sometime DBDs have poor to no support for bind variables

=head1 DESCRIPTION

This class allows queries to work when the DBD or underlying library does not
support the usual C<?> placeholders, or at least doesn't support them very
well, as is the case with L<DBD::Sybase>

=head1 METHODS

=head2 sth

Uses C<prepare> instead of the usual C<prepare_cached>, seeing as we can't cache very effectively without bind variables.

=cut

sub _dbh_sth {
  my ($self, $dbh, $sql) = @_;
  $dbh->prepare($sql);
}

=head2 _prep_for_execute

Manually subs in the values for the usual C<?> placeholders.

=cut

sub _prep_for_execute {
  my $self = shift;
  my ($sql, @bind) = $self->next::method(@_);

  $sql =~ s/\?/$self->_dbh->quote($_)/e for (@bind);

  return ($sql);
}

=head1 AUTHORS

Brandon Black <blblack@gmail.com>

Trym Skaar <trym@tryms.no>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
