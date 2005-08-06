package DBIx::Class::CDBICompat::ImaDBI;

use strict;
use warnings;
use DBIx::ContextualFetch;

use NEXT;
use base qw/Class::Data::Inheritable/;

__PACKAGE__->mk_classdata('_transform_sql_handler_order'
                            => [ qw/TABLE ESSENTIAL JOIN/ ] );

__PACKAGE__->mk_classdata('_transform_sql_handlers' =>
  {
    'TABLE' =>
      sub {
        my ($self, $class, $data) = @_;
        return $class->_table_name unless $data;
        my ($f_class, $alias) = split(/=/, $data);
        $f_class ||= $class;
        $self->{_classes}{$alias} = $f_class;
        return $f_class->_table_name." ${alias}";
      },
    'ESSENTIAL' =>
      sub {
        my ($self, $class, $data) = @_;
        return join(' ', $class->columns('Essential')) unless $data;
        return join(' ', $self->{_classes}{$data}->columns('Essential'));
      },
    'JOIN' =>
      sub {
        my ($self, $class, $data) = @_;
        my ($from, $to) = split(/ /, $data);
        my ($from_class, $to_class) = @{$self->{_classes}}{$from, $to};
        my ($rel_obj) = grep { $_->{class} && $_->{class} eq $to_class }
                          values %{ $from_class->_relationships };
        unless ($rel_obj) {
          ($from, $to) = ($to, $from);
          ($from_class, $to_class) = ($to_class, $from_class);
          ($rel_obj) = grep { $_->{class} && $_->{class} eq $to_class }
                         values %{ $from_class->_relationships };
        }
        $self->throw( "No relationship to JOIN from ${from_class} to ${to_class}" )
          unless $rel_obj;
        my $attrs = {
          %$self,
          _aliases => { self => $from, foreign => $to },
          _action => 'join',
        };
        my $join = $from_class->_cond_resolve($rel_obj->{cond}, $attrs);
        return $join;
      }
        
  } );

sub db_Main {
  return $_[0]->storage->dbh;
}

sub connection {
  my ($class, @info) = @_;
  $info[3] = { %{ $info[3] || {}} };
  $info[3]->{RootClass} = 'DBIx::ContextualFetch';
  return $class->NEXT::connection(@info);
}

sub __driver {
  return $_[0]->storage->dbh->{Driver}->{Name};
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
      return $class->storage->sth($class->transform_sql($sql, @_));
    };
  if ($sql =~ /select/i) {
    my $meth = "sql_${name}";
    *{"${class}::search_${name}"} =
      sub {
        my ($class, @args) = @_;
        my $sth = $class->$meth;
        $sth->execute(@args);
        return $class->sth_to_objects($sth);
      };
  }
}

sub sth_to_objects {
  my ($class, $sth) = @_;
  my @cols = $class->_select_columns;
  my @ret;
  while (my @row = $sth->fetchrow_array) {
    push(@ret, $class->_row_to_object(\@cols,\@row));
  }
  return @ret;
}

sub transform_sql {
  my ($class, $sql, @args) = @_;
  my $table = $class->_table_name;
  my $attrs = { };
  foreach my $key (@{$class->_transform_sql_handler_order}) {
    my $h = $class->_transform_sql_handlers->{$key};
    $sql =~ s/__$key(?:\(([^\)]+)\))?__/$h->($attrs, $class, $1)/eg;
  }
  return sprintf($sql, @args);
}

package DBIx::ContextualFetch::st;

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
