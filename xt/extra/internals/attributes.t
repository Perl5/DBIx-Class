use warnings;
use strict;

use Config;
my $skip_threads;
BEGIN {
  if( ! $Config{useithreads} ) {
    $skip_threads = 'your perl does not support ithreads';
  }
  elsif( "$]" < 5.008005 ) {
    $skip_threads = 'DBIC does not actively support threads before perl 5.8.5';
  }
  elsif( $INC{'Devel/Cover.pm'} ) {
    $skip_threads = 'Devel::Cover does not work with ithreads yet';
  }

  unless( $skip_threads ) {
    require threads;
    threads->import;
  }
}

use Test::More;
use DBIx::Class::_Util qw( quote_sub modver_gt_or_eq );

### Test the upcoming attributes support
require DBIx::Class;
@DBICTest::ATTRTEST::ISA  = 'DBIx::Class';

my $var = \42;
my $s = quote_sub(
  'DBICTest::ATTRTEST::attr',
  '$v',
  { '$v' => $var },
  {
    attributes => [qw( ResultSet )],
    package => 'DBICTest::ATTRTEST',
  },
);

is $s, \&DBICTest::ATTRTEST::attr, 'Same cref installed';

is DBICTest::ATTRTEST::attr(), 42, 'Sub properly installed and callable';

is_deeply
  [ attributes::get( $s ) ],
  [ 'ResultSet' ],
  'Attribute installed',
unless $^V =~ /c/; # FIXME work around https://github.com/perl11/cperl/issues/147

sub add_more_attrs {
  # Test that secondary attribute application works
  attributes->import(
    'DBICTest::ATTRTEST',
    DBICTest::ATTRTEST->can('attr'),
    'method',
    'SomethingNobodyUses',
  );

  # and that double-application also works
  attributes->import(
    'DBICTest::ATTRTEST',
    DBICTest::ATTRTEST->can('attr'),
    'SomethingNobodyUses',
  );

  is_deeply
    [ sort( attributes::get( $s ) )],
    [
      qw( ResultSet SomethingNobodyUses method ),

      # before 5.10/5.8.9 internal reserved would get doubled, sigh
      #
      # FIXME - perhaps need to weed them out somehow at FETCH_CODE_ATTRIBUTES
      # time...? In any case - this is not important at this stage
      ( modver_gt_or_eq( attributes => '0.08' ) ? () : 'method' )
    ],
    'Secondary attributes installed',
  unless $^V =~ /c/; # FIXME work around https://github.com/perl11/cperl/issues/147

  is_deeply (
    DBICTest::ATTRTEST->_attr_cache->{$s},
    [
      qw( ResultSet SomethingNobodyUses ),

      # after 5.10/5.8.9 FETCH_CODE_ATTRIBUTES is never called for reserved
      # attribute names, so there is nothing for DBIC to see
      #
      # FIXME - perhaps need to teach ->_attr to reinvoke attributes::get() ?
      # In any case - this is not important at this stage
      ( modver_gt_or_eq( attributes => '0.08' ) ? () : 'method' )
    ],
    'Attributes visible in DBIC-specific attribute API',
  );
}


if ($skip_threads) {
  SKIP: { skip "Skipping the thread test: $skip_threads", 1 }

  add_more_attrs();
}
else {
  threads->create(sub {
    add_more_attrs();
    select( undef, undef, undef, 0.2 ); # without this many tasty crashes even on latest perls
  })->join;
}


done_testing;
