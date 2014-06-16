package DBICTest::DynamicForeignCols::TestComputer;

use warnings;
use strict;

use base 'DBIx::Class::Core';

__PACKAGE__->table('TestComputer');
__PACKAGE__->add_columns(qw( test_id ));
__PACKAGE__->_add_join_column({ class => 'DBICTest::DynamicForeignCols::Computer', method => 'computer' });
__PACKAGE__->set_primary_key('test_id', 'computer_id');
__PACKAGE__->belongs_to(computer => 'DBICTest::DynamicForeignCols::Computer', 'computer_id');

###
### This is a pathological case lifted from production. Yes, there is code
### like this in the wild
###
sub _add_join_column {
   my ($self, $params) = @_;

   my $class = $params->{class};
   my $method = $params->{method};

   $self->ensure_class_loaded($class);

   my @class_columns = $class->primary_columns;

   if (@class_columns = 1) {
      $self->add_columns( "${method}_id" );
   } else {
      my $i = 0;
      for (@class_columns) {
         $i++;
         $self->add_columns( "${method}_${i}_id" );
      }
   }
}

1;
