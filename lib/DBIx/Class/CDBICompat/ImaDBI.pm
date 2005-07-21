package DBIx::Class::CDBICompat::ImaDBI;

use strict;
use warnings;

use NEXT;

sub db_Main {
  return $_[0]->_get_dbh;
}

sub _dbi_connect {
  my ($class, @info) = @_;
  $info[3] = { %{ $info[3] || {}} };
  $info[3]->{RootClass} = 'DBIx::ContextualFetch';
  return $class->NEXT::_dbi_connect(@info);
}

sub __driver {
  return $_[0]->_get_dbh->{Driver}->{Name};
}

sub set_sql {
  my ($class, $name, $sql) = @_;
  my $table = $class->_table_name;
  #$sql =~ s/__TABLE__/$table/;
  no strict 'refs';
  *{"${class}::sql_${name}"} =
    sub {
      my $sql = $sql;
      my $class = shift;
      return $class->_sql_to_sth($class->transform_sql($sql, @_));
    };
  if ($sql =~ /select/i) {
    my $meth = "sql_${name}";
    *{"${class}::search_${name}"} =
      sub {
        my ($class, @args) = @_;
        $class->sth_to_objects($class->$meth, \@args);
      };
  }
}

sub transform_sql {
  my ($class, $sql, @args) = @_;
  my $table = $class->_table_name;
  $sql =~ s/__TABLE__/$table/g;
  $sql =~ s/__ESSENTIAL__/join(' ', $class->columns('Essential'))/eg;
  return sprintf($sql, @args);
}

1;
