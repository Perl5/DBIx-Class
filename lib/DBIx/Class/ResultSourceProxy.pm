package # hide from PAUSE
    DBIx::Class::ResultSourceProxy;

use strict;
use warnings;

use base 'DBIx::Class';
use mro 'c3';

use DBIx::Class::_Util qw( quote_sub fail_on_internal_call );
use namespace::clean;

__PACKAGE__->mk_group_accessors('inherited_ro_instance' => 'source_name');

sub get_inherited_ro_instance { $_[0]->get_inherited($_[1]) }

sub set_inherited_ro_instance {
  $_[0]->throw_exception ("Cannot set '$_[1]' on an instance")
    if length ref $_[0];

  $_[0]->set_inherited( $_[1], $_[2] );
}


sub add_columns {
  my ($class, @cols) = @_;
  my $source = $class->result_source_instance;
  $source->add_columns(@cols);
  foreach my $c (grep { !ref } @cols) {
    # If this is an augment definition get the real colname.
    $c =~ s/^\+//;

    $class->register_column($c => $source->column_info($c));
  }
}

sub add_column {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->add_columns(@_)
}


sub add_relationship {
  my ($class, $rel, @rest) = @_;
  my $source = $class->result_source_instance;
  $source->add_relationship($rel => @rest);
  $class->register_relationship($rel => $source->relationship_info($rel));
}


# legacy resultset_class accessor, seems to be used by cdbi only
sub iterator_class {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->result_source_instance->resultset_class(@_)
}

for my $method_to_proxy (qw/
  source_info
  result_class
  resultset_class
  resultset_attributes

  columns
  has_column

  remove_column
  remove_columns

  column_info
  columns_info
  column_info_from_storage

  set_primary_key
  primary_columns
  sequence

  add_unique_constraint
  add_unique_constraints

  unique_constraints
  unique_constraint_names
  unique_constraint_columns

  relationships
  relationship_info
  has_relationship
/) {
  quote_sub __PACKAGE__."::$method_to_proxy", sprintf( <<'EOC', $method_to_proxy );
    DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and DBIx::Class::_Util::fail_on_internal_call;
    shift->result_source_instance->%s (@_);
EOC

}

1;
