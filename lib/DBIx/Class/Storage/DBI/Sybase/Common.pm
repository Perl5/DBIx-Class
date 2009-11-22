package DBIx::Class::Storage::DBI::Sybase::Common;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::Common - Common functionality for drivers using
DBD::Sybase

=head1 DESCRIPTION

This is the base class for L<DBIx::Class::Storage::DBI::Sybase> and
L<DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server>. It provides some
utility methods related to L<DBD::Sybase> and the supported functions of the
database you are connecting to.

=head1 METHODS

=cut

sub _ping {
  my $self = shift;

  my $dbh = $self->_dbh or return 0;

  local $dbh->{RaiseError} = 1;
  local $dbh->{PrintError} = 0;

  if ($dbh->{syb_no_child_con}) {
# if extra connections are not allowed, then ->ping is reliable
    my $ping = eval { $dbh->ping };
    return $@ ? 0 : $ping;
  }

  eval {
# XXX if the main connection goes stale, does opening another for this statement
# really determine anything?
    $dbh->do('select 1');
  };

  return $@ ? 0 : 1;
}

sub _set_max_connect {
  my $self = shift;
  my $val  = shift || 256;

  my $dsn = $self->_dbi_connect_info->[0];

  return if ref($dsn) eq 'CODE';

  if ($dsn !~ /maxConnect=/) {
    $self->_dbi_connect_info->[0] = "$dsn;maxConnect=$val";
    my $connected = defined $self->_dbh;
    $self->disconnect;
    $self->ensure_connected if $connected;
  }
}

=head2 using_freetds

Whether or not L<DBD::Sybase> was compiled against FreeTDS. If false, it means
the Sybase OpenClient libraries were used.

=cut

sub using_freetds {
  my $self = shift;

  return $self->_get_dbh->{syb_oc_version} =~ /freetds/i;
}

=head2 set_textsize

When using FreeTDS and/or MSSQL, C<< $dbh->{LongReadLen} >> is not available,
use this function instead. It does:

  $dbh->do("SET TEXTSIZE $bytes");

Takes the number of bytes, or uses the C<LongReadLen> value from your
L<DBIx::Class/connect_info> if omitted, lastly falls back to the C<32768> which
is the L<DBD::Sybase> default.

=cut

sub set_textsize {
  my $self = shift;
  my $text_size = shift ||
    eval { $self->_dbi_connect_info->[-1]->{LongReadLen} } ||
    32768; # the DBD::Sybase default

  return unless defined $text_size;

  $self->_dbh->do("SET TEXTSIZE $text_size");
}

1;

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
