package # hide from the pauses
  DBIx::Class::_TempExtlib;

use strict;
use warnings;
use File::Spec;
use Module::Runtime;

# There can be only one of these, make sure we get the bundled part and
# *not* something off the site lib
for (qw(
  DBIx::Class::SQLMaker
  SQL::Abstract
  SQL::Abstract::Test
)) {
  if ($INC{Module::Runtime::module_notional_filename($_)}) {
    die "\nUnable to continue - a part of the bundled templib contents "
      . "was already loaded (likely an older version from CPAN). "
      . "Make sure that @{[ __PACKAGE__ ]} is loaded before $_\n\n"
    ;
  }
}

our ($HERE) = File::Spec->rel2abs(
  File::Spec->catdir( (File::Spec->splitpath(__FILE__))[1], '_TempExtlib' )
) =~ /^(.*)$/; # screw you, taint mode

unshift @INC, $HERE;

1;
