use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

{
  my $clone = $schema->clone;
  cmp_ok ($clone->storage, 'eq', $schema->storage, 'Storage copied into new schema (not a new instance)');
}

{
  is $schema->custom_attr, undef;
  my $clone = $schema->clone(custom_attr => 'moo');
  is $clone->custom_attr, 'moo', 'cloning can change existing attrs';
}

{
  my $clone = $schema->clone({ custom_attr => 'moo' });
  is $clone->custom_attr, 'moo', 'cloning can change existing attrs';
}


done_testing;
