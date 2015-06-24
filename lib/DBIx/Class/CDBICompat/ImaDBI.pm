package # hide from PAUSE
    DBIx::Class::CDBICompat::ImaDBI;

use strict;
use warnings;
use DBIx::ContextualFetch;
use DBIx::Class::_Util qw(quote_sub perlstring);

use base qw(Class::Data::Inheritable);

__PACKAGE__->mk_classdata('sql_transformer_class' =>
                          'DBIx::Class::CDBICompat::SQLTransformer');

__PACKAGE__->mk_classdata('_transform_sql_handler_order'
                            => [ qw/TABLE ESSENTIAL JOIN IDENTIFIER/ ] );

__PACKAGE__->mk_classdata('_transform_sql_handlers' => {} );

sub db_Main {
  return $_[0]->storage->dbh;
}

sub connection {
  my ($class, @info) = @_;
  $info[3] = { %{ $info[3] || {}} };
  $info[3]->{RootClass} = 'DBIx::ContextualFetch';
  return $class->next::method(@info);
}

sub __driver {
  return $_[0]->storage->dbh->{Driver}->{Name};
}

sub set_sql {
  my ($class, $name, $sql) = @_;

  quote_sub "${class}::sql_${name}", sprintf( <<'EOC', perlstring $sql );
    my $class = shift;
    return $class->storage->dbh_do(
      _prepare_sth => $class->transform_sql(%s, @_)
    );
EOC


  if ($sql =~ /select/i) {  # FIXME - this should be anchore surely...?
    quote_sub "${class}::search_${name}", sprintf( <<'EOC', "sql_$name" );
      my ($class, @args) = @_;
      $class->sth_to_objects( $class->%s, \@args);
EOC
  }
}

sub sth_to_objects {
  my ($class, $sth, $execute_args) = @_;

  $sth->execute(@$execute_args);

  my @ret;
  while (my $row = $sth->fetchrow_hashref) {
    push(@ret, $class->inflate_result($class->result_source_instance, $row));
  }

  return @ret;
}

sub transform_sql {
  my ($class, $sql, @args) = @_;

  my $tclass = $class->sql_transformer_class;
  $class->ensure_class_loaded($tclass);
  my $t = $tclass->new($class, $sql, @args);

  return sprintf($t->sql, $t->args);
}

package
  DBIx::ContextualFetch::st; # HIDE FROM PAUSE THIS IS NOT OUR CLASS

no warnings 'redefine';

sub _untaint_execute {
  my $sth = shift;
  my $old_value = $sth->{Taint};
  $sth->{Taint} = 0;
  my $ret;
  {
    no warnings 'uninitialized';
    $ret = $sth->SUPER::execute(@_);
  }
  $sth->{Taint} = $old_value;
  return $ret;
}

1;
