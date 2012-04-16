package DBIx::Class::Storage::DBI::Firebird::Common;

use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';
use List::Util 'first';
use namespace::clean;

=head1 NAME

DBIx::Class::Storage::DBI::Firebird::Common - Driver Base Class for the Firebird RDBMS

=head1 DESCRIPTION

This class implements autoincrements for Firebird using C<RETURNING> as well as
L<auto_nextval|DBIx::Class::ResultSource/auto_nextval>, savepoints and server
version detection.

=cut

# set default
__PACKAGE__->_use_insert_returning (1);
__PACKAGE__->sql_limit_dialect ('FirstSkip');
__PACKAGE__->sql_quote_char ('"');

sub _sequence_fetch {
  my ($self, $nextval, $sequence) = @_;

  $self->throw_exception("Can only fetch 'nextval' for a sequence")
    if $nextval !~ /^nextval$/i;

  $self->throw_exception('No sequence to fetch') unless $sequence;

  my ($val) = $self->_get_dbh->selectrow_array(sprintf
    'SELECT GEN_ID(%s, 1) FROM rdb$database',
    $self->sql_maker->_quote($sequence)
  );

  return $val;
}

sub _dbh_get_autoinc_seq {
  my ($self, $dbh, $source, $col) = @_;

  my $table_name = $source->from;
  $table_name    = $$table_name if ref $table_name;
  $table_name    = $self->sql_maker->quote_char ? $table_name : uc($table_name);

  local $dbh->{LongReadLen} = 100000;
  local $dbh->{LongTruncOk} = 1;

  my $sth = $dbh->prepare(<<'EOF');
SELECT t.rdb$trigger_source
FROM rdb$triggers t
WHERE t.rdb$relation_name = ?
AND t.rdb$system_flag = 0 -- user defined
AND t.rdb$trigger_type = 1 -- BEFORE INSERT
EOF
  $sth->execute($table_name);

  while (my ($trigger) = $sth->fetchrow_array) {
    my @trig_cols = map {
      /^"([^"]+)/ ? $1 : uc($1)
    } $trigger =~ /new\.("?\w+"?)/ig;

    my ($quoted, $generator) = $trigger =~
/(?:gen_id\s* \( \s* |next \s* value \s* for \s*)(")?(\w+)/ix;

    if ($generator) {
      $generator = uc $generator unless $quoted;

      return $generator
        if first {
          $self->sql_maker->quote_char ? ($_ eq $col) : (uc($_) eq uc($col))
        } @trig_cols;
    }
  }

  return undef;
}

sub _exec_svp_begin {
  my ($self, $name) = @_;

  $self->_dbh->do("SAVEPOINT $name");
}

sub _exec_svp_release {
  my ($self, $name) = @_;

  $self->_dbh->do("RELEASE SAVEPOINT $name");
}

sub _exec_svp_rollback {
  my ($self, $name) = @_;

  $self->_dbh->do("ROLLBACK TO SAVEPOINT $name")
}

# http://www.firebirdfaq.org/faq223/
sub _get_server_version {
  my $self = shift;

  return $self->_get_dbh->selectrow_array(q{
SELECT rdb$get_context('SYSTEM', 'ENGINE_VERSION') FROM rdb$database
  });
}

1;

=head1 CAVEATS

=over 4

=item *

C<last_insert_id> support by default only works for Firebird versions 2 or
greater, L<auto_nextval|DBIx::Class::ResultSource/auto_nextval> however should
work with earlier versions.

=back

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:
