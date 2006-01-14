sub run_tests {
my $schema = shift;

# this test will check to see if you can have 2 columns
# in the same class pointing at the same other class
#
# example:
#
# +---------+       +--------------+
# | SelfRef |       | SelfRefAlias |
# +---------+  1-M  +--------------+
# | id      |-------| self_ref     | --+
# | name    |       | alias        | --+
# +---------+       +--------------+   |
#    /|\                               |
#     |                                |
#     +--------------------------------+
#
# see http://use.perl.org/~LTjake/journal/24876 for the
# issue with CDBI

plan tests => 4;

my $item = $schema->class("SelfRef")->find( 1 );
is( $item->name, 'First', 'proper start item' );

my @aliases = $item->aliases;

is( scalar @aliases, 1, 'proper number of aliases' );

my $orig  = $aliases[ 0 ]->self_ref;
my $alias = $aliases[ 0 ]->alias;

is( $orig->name, 'First', 'proper original' );
is( $alias->name, 'Second', 'proper alias' );

}

1;
