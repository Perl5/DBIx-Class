package DBIx::Class::Storage::DBI::Sybase;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

use Carp::Clan qw/^DBIx::Class/;

sub _rebless {
  my $self = shift;

  if (ref($self) eq 'DBIx::Class::Storage::DBI::Sybase') {
    my $dbtype = eval {
      @{$self->dbh->selectrow_arrayref(qq{sp_server_info \@attribute_id=1})}[2]
    } || '';

    my $exception = $@;
    $dbtype =~ s/\W/_/gi;
    my $subclass = "DBIx::Class::Storage::DBI::Sybase::${dbtype}";

    if (!$exception && $dbtype && $self->load_optional_class($subclass)) {
      bless $self, $subclass;
      $self->_rebless;
    } elsif (not $self->dbh->{syb_dynamic_supported}) {
      bless $self, 'DBIx::Class::Storage:DBI::Sybase::NoBindVars';
      $self->_rebless;
    }
  }
}

{
  my $old_dbd_warned = 0;

  sub _populate_dbh {
    my $self = shift;
    $self->next::method(@_);
    my $dbh = $self->_dbh;

    if ($dbh->can('syb_date_fmt')) {
      $dbh->syb_date_fmt('ISO_strict');
    } elsif (not $old_dbd_warned) {
      carp "Your DBD::Sybase is too old to support ".
      "DBIx::Class::InflateColumn::DateTime, please upgrade!";
      $old_dbd_warned = 1;
    }

    $dbh->do('set dateformat mdy');

    1;
  }
}

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col) = @_;

  # sorry, there's no other way!
  my $sth = $dbh->prepare_cached("select max($col) from ".$source->from);
  return ($dbh->selectrow_array($sth))[0];
}

sub count {
  my ($self, $source, $attrs) = @_;

  if (exists $attrs->{rows}) {
    my $new_attrs = $self->_trim_attributes_for_count($source, $attrs);

    $new_attrs->{select} = '1';
    $new_attrs->{as}     = ['dummy'];

# speed things up at least *a little*
    $new_attrs->{result_class} = 'DBIx::Class::ResultClass::HashRefInflator';

    my $offset = $attrs->{offset} || 0;
    my $total  = $attrs->{rows} + $offset;
    
    $self->dbh->do("set rowcount $total");

    my $tmp_rs = $source->resultset_class->new($source, $new_attrs);
    
    my $count = 0;
    $count++ while $tmp_rs->cursor->next;

    $self->dbh->do("set rowcount 0");

    return $count;
  }

  return $self->next::method(@_);
}

sub datetime_parser_type { "DBIx::Class::Storage::DBI::Sybase::DateTime" }

1;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase - Storage::DBI subclass for Sybase

=head1 SYNOPSIS

This subclass supports L<DBD::Sybase> for real Sybase databases.  If you are
using an MSSQL database via L<DBD::Sybase>, your storage will be reblessed to
L<DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server>.

=head1 DESCRIPTION

If your version of Sybase does not support placeholders, then your storage
will be reblessed to L<DBIx::Class::Storage::DBI::Sybase::NoBindVars>. You can
also enable that driver explicitly, see the documentation for more details.

With this driver there is unfortunately no way to get the C<last_insert_id>
without doing a C<select max(col)>.

But your queries will be cached.

=head1 DATES

On connection C<syb_date_fmt> is set to C<ISO_strict>, e.g.:
C<2004-08-21T14:36:48.080Z> and C<dateformat> is set to C<mdy>, e.g.:
C<08/13/1979 18:08:55.080>.

This works for both C<DATETIME> and C<SMALLDATETIME> columns, although
C<SMALLDATETIME> columns only have minute precision.

You will need the L<DateTime::Format::Strptime> module if you are going to use
L<DBIx::Class::InflateColumn::DateTime>.

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:
