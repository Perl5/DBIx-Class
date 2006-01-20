package DBIx::Class::ResultSourceInstance;

use strict;
use warnings;

use base qw/DBIx::Class/;

sub iterator_class { shift->result_source_instance->resultset_class(@_) }
sub resultset_class { shift->result_source_instance->resultset_class(@_) }

sub add_columns {
  my ($class, @cols) = @_;
  my $source = $class->result_source_instance;
  $source->add_columns(@cols);
  foreach my $c (grep { !ref } @cols) {
    $class->register_column($c => $source->column_info($c));
  }
}

sub _select_columns {
  return shift->result_source_instance->columns;
}

sub has_column {                                                                
  my ($self, $column) = @_;                                                     
  return $self->result_source_instance->has_column($column);                    
}

sub column_info {                                                               
  my ($self, $column) = @_;                                                     
  return $self->result_source_instance->column_info($column);                   
}

                                                                                
sub columns {                                                                   
  return shift->result_source_instance->columns(@_);                            
}                                                                               
                                                                                
sub set_primary_key { shift->result_source_instance->set_primary_key(@_); }     
sub primary_columns { shift->result_source_instance->primary_columns(@_); }

sub add_relationship {
  shift->result_source_instance->add_relationship(@_);
}

sub relationships {
  shift->result_source_instance->relationships(@_);
}

sub relationship_info {
  shift->result_source_instance->relationship_info(@_);
}

1;
