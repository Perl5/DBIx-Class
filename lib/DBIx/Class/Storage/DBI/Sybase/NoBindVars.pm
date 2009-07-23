package DBIx::Class::Storage::DBI::Sybase::NoBindVars;

use Class::C3;
use base qw/
  DBIx::Class::Storage::DBI::NoBindVars
  DBIx::Class::Storage::DBI::Sybase
/;
use List::Util ();
use Scalar::Util ();

sub _rebless {
  my $self = shift;
  $self->disable_sth_caching(1);
}

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col) = @_;

  # @@identity works only if not using placeholders
  # Should this query be cached?
  return ($dbh->selectrow_array('select @@identity'))[0];
}

my $number = sub { Scalar::Util::looks_like_number($_[0]) };

my $decimal = sub { $_[0] =~ /^ [-+]? \d+ (?:\.\d*)? \z/x };

my %noquote = (
    int => sub { $_[0] =~ /^ [-+]? \d+ \z/x },
    bit => => sub { $_[0] =~ /^[01]\z/ },
    money => sub { $_[0] =~ /^\$ \d+ (?:\.\d*)? \z/x },
    float => $number,
    real => $number,
    double => $number,
    decimal => $decimal,
    numeric => $decimal,
);

sub should_quote_value {
  my $self = shift;
  my ($type, $value) = @_;

  return $self->next::method(@_) if not defined $value or not defined $type;

  if (my $key = List::Util::first { $type =~ /$_/i } keys %noquote) {
    return 0 if $noquote{$key}->($value);
  } elsif($self->is_datatype_numeric($type) && $number->($value)) {
    return 0;
  }

## try to guess based on value
#  elsif (not $type) {
#    return 0 if $number->($value) || $noquote->{money}->($value);
#  }

  return $self->next::method(@_);
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::NoBindVars - Storage::DBI subclass for Sybase
without placeholder support

=head1 DESCRIPTION

If you're using this driver than your version of Sybase does not support
placeholders, or your version of L<DBD::Sybase> was compiled with FreeTDS rather
than the Sybase OpenClient libraries. You can check with:

  $dbh->{syb_dynamic_supported}

To see if you are using FreeTDS, run:

  perl -MDBI -le 'my $dbh = DBI->connect($dsn, $user, $pass); print $dbh->{syb_oc_version}'

You will get a warning on startup if you're using FreeTDS in any case.

You can also enable this driver explicitly using:

  my $schema = SchemaClass->clone;
  $schema->storage_type('::DBI::Sybase::NoBindVars');
  $schema->connect($dsn, $user, $pass, \%opts);

See the discussion in L<< DBD::Sybase/Using ? Placeholders & bind parameters to
$sth->execute >> for details on the pros and cons of using placeholders.

One advantage of not using placeholders is that C<select @@identity> will work
for obtainging the last insert id of an C<IDENTITY> column, instead of having to
do C<select max(col)> as the base Sybase driver does.

When using this driver, bind variables will be interpolated (properly quoted of
course) into the SQL query itself, without using placeholders.

The caching of prepared statements is also explicitly disabled, as the
interpolation renders it useless.

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:
