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
use Test::Exception;
use DBIx::Class::_Util qw( quote_sub );

require DBIx::Class;
@DBICTest::AttrLegacy::ISA  = 'DBIx::Class';
sub DBICTest::AttrLegacy::VALID_DBIC_CODE_ATTRIBUTE { 1 }

my $var = \42;
my $s = quote_sub(
  'DBICTest::AttrLegacy::attr',
  '$v',
  { '$v' => $var },
  {
    attributes => [qw( ResultSet DBIC_random_attr )],
    package => 'DBICTest::AttrLegacy',
  },
);

is $s, \&DBICTest::AttrLegacy::attr, 'Same cref installed';

is DBICTest::AttrLegacy::attr(), 42, 'Sub properly installed and callable';

is_deeply
  [ sort( attributes::get( $s ) ) ],
  [qw( DBIC_random_attr ResultSet )],
  'Attribute installed',
unless $^V =~ /c/; # FIXME work around https://github.com/perl11/cperl/issues/147


@DBICTest::AttrTest::ISA  = 'DBIx::Class';
{
    package DBICTest::AttrTest;

    eval <<'EOS' or die $@;
      sub VALID_DBIC_CODE_ATTRIBUTE { $_[1] =~ /DBIC_attr/ }
      sub attr :lvalue :method :DBIC_attr1 { $$var}
      1;
EOS

    ::throws_ok {
      attributes->import(
        'DBICTest::AttrTest',
        DBICTest::AttrTest->can('attr'),
        'DBIC_unknownattr',
      );
    } qr/DBIC-specific attribute 'DBIC_unknownattr' did not pass validation/;
}

is_deeply
  [ sort( attributes::get( DBICTest::AttrTest->can("attr") )) ],
  [qw( DBIC_attr1 lvalue method )],
  'Attribute installed',
unless $^V =~ /c/; # FIXME work around https://github.com/perl11/cperl/issues/147

ok(
  ! DBICTest::AttrTest->can('__attr_cache'),
  'Inherited classdata never created on core attrs'
);

is_deeply(
  DBICTest::AttrTest->_attr_cache,
  {},
  'Cache never instantiated on core attrs'
);

sub add_more_attrs {
  # Test that secondary attribute application works
  attributes->import(
    'DBICTest::AttrLegacy',
    DBICTest::AttrLegacy->can('attr'),
    'SomethingNobodyUses',
  );

  # and that double-application also works
  attributes->import(
    'DBICTest::AttrLegacy',
    DBICTest::AttrLegacy->can('attr'),
    'SomethingNobodyUses',
  );

  is_deeply
    [ sort( attributes::get( $s ) )],
    [ qw( DBIC_random_attr ResultSet SomethingNobodyUses ) ],
    'Secondary attributes installed',
  unless $^V =~ /c/; # FIXME work around https://github.com/perl11/cperl/issues/147

  is_deeply (
    DBICTest::AttrLegacy->_attr_cache->{$s},
    [ qw( ResultSet SomethingNobodyUses ) ],
    'Attributes visible in legacy DBIC attribute API',
  );



  # Test that secondary attribute application works
  attributes->import(
    'DBICTest::AttrTest',
    DBICTest::AttrTest->can('attr'),
    'DBIC_attr2',
  );

  # and that double-application also works
  attributes->import(
    'DBICTest::AttrTest',
    DBICTest::AttrTest->can('attr'),
    'DBIC_attr2',
    'DBIC_attr3',
  );

  is_deeply
    [ sort( attributes::get( DBICTest::AttrTest->can("attr") )) ],
    [qw( DBIC_attr1 DBIC_attr2 DBIC_attr3 lvalue method )],
    'DBIC-specific attribute installed',
  unless $^V =~ /c/; # FIXME work around https://github.com/perl11/cperl/issues/147

  ok(
    ! DBICTest::AttrTest->can('__attr_cache'),
    'Inherited classdata never created on core+DBIC-specific attrs'
  );

  is_deeply(
    DBICTest::AttrTest->_attr_cache,
    {},
    'Legacy DBIC attribute cache never instantiated on core+DBIC-specific attrs'
  );
}


if ($skip_threads) {
  SKIP: { skip "Skipping the thread test: $skip_threads", 1 }

  add_more_attrs();
}
else {
  threads->create(sub {

    threads->create(sub {

      add_more_attrs();
      select( undef, undef, undef, 0.2 ); # without this many tasty crashes even on latest perls

    })->join;

    select( undef, undef, undef, 0.2 ); # without this many tasty crashes even on latest perls

  })->join;
}

done_testing;
