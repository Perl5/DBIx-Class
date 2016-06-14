BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

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
use DBIx::Class::_Util qw( quote_sub describe_class_methods serialize refdesc );
use List::Util 'shuffle';
use Errno ();

use DBICTest;

my $pkg_gen_history = {};

sub grab_pkg_gen ($) {
  push @{ $pkg_gen_history->{$_[0]} }, [
    DBIx::Class::_Util::get_real_pkg_gen($_[0]),
    'line ' . ( (caller(0))[2] ),
  ];
}

@DBICTest::AttrLegacy::ISA  = 'DBIx::Class';
sub DBICTest::AttrLegacy::VALID_DBIC_CODE_ATTRIBUTE { 1 }

grab_pkg_gen("DBICTest::AttrLegacy");

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

grab_pkg_gen("DBICTest::AttrLegacy");

is $s, \&DBICTest::AttrLegacy::attr, 'Same cref installed';

is DBICTest::AttrLegacy::attr(), 42, 'Sub properly installed and callable';

is_deeply
  [ sort( attributes::get( $s ) ) ],
  [qw( DBIC_random_attr ResultSet )],
  'Attribute installed',
;

{
  package DBICTest::SomeGrandParentClass;
  use base 'DBIx::Class::MethodAttributes';
  sub VALID_DBIC_CODE_ATTRIBUTE { shift->next::method(@_) };
}
{
  package DBICTest::SomeParentClass;
  use base qw(DBICTest::SomeGrandParentClass);
}
{
  package DBICTest::AnotherParentClass;
  use base 'DBIx::Class::MethodAttributes';
  sub VALID_DBIC_CODE_ATTRIBUTE { $_[1] =~ /DBIC_attr/ };
}

{
  package DBICTest::AttrTest;

  @DBICTest::AttrTest::ISA = qw( DBICTest::SomeParentClass DBICTest::AnotherParentClass );
  use mro 'c3';

  ::grab_pkg_gen("DBICTest::AttrTest");

  eval <<'EOS' or die $@;
      sub attr :lvalue :method :DBIC_attr1 { $$var}
      1;
EOS

  ::grab_pkg_gen("DBICTest::AttrTest");

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
;

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

  grab_pkg_gen("DBICTest::AttrLegacy");

  is_deeply
    [ sort( attributes::get( $s ) )],
    [ qw( DBIC_random_attr ResultSet SomethingNobodyUses ) ],
    'Secondary attributes installed',
  ;

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

  grab_pkg_gen("DBICTest::AttrTest");

  # and that double-application also works
  attributes->import(
    'DBICTest::AttrTest',
    DBICTest::AttrTest->can('attr'),
    'DBIC_attr2',
    'DBIC_attr3',
  );

  grab_pkg_gen("DBICTest::AttrTest");

  is_deeply
    [ sort( attributes::get( DBICTest::AttrTest->can("attr") )) ],
    [qw( DBIC_attr1 DBIC_attr2 DBIC_attr3 lvalue method )],
    'DBIC-specific attribute installed',
  ;

  ok(
    ! DBICTest::AttrTest->can('__attr_cache'),
    'Inherited classdata never created on core+DBIC-specific attrs'
  );

  is_deeply(
    DBICTest::AttrTest->_attr_cache,
    {},
    'Legacy DBIC attribute cache never instantiated on core+DBIC-specific attrs'
  );

  # no point dragging in threads::shared, just do the check here
  for my $class ( keys %$pkg_gen_history ) {
    my $stack = $pkg_gen_history->{$class};

    for my $i ( 1 .. $#$stack ) {
      cmp_ok(
        $stack->[$i-1][0],
          ( DBIx::Class::_ENV_::OLD_MRO ? '!=' : '<' ),
        $stack->[$i][0],
        "pkg_gen for $class changed from $stack->[$i-1][1] to $stack->[$i][1]"
      );
    }
  }

  my $cnt;
  # check that class description is stable, and changes when needed
  for my $class (qw(
    DBICTest::AttrTest
    DBICTest::AttrLegacy
    DBIx::Class
    main
  )) {
    my $desc = describe_class_methods($class);

    is_deeply(
      describe_class_methods($class),
      $desc,
      "describe_class_methods result is stable over '$class' (pass $_)"
    ) for (1,2,3);

    my $desc2 = do {
      no warnings 'once';
      no strict 'refs';

      $cnt++;

      eval "sub UNIVERSAL::some_unimethod_$cnt {}; 1" or die $@;

      my $rv = describe_class_methods($class);

      delete ${"UNIVERSAL::"}{"some_unimethod_$cnt"};

      $rv
    };

    delete $_->{cumulative_gen} for $desc, $desc2;
    ok(
      serialize( $desc )
        ne
      serialize( $desc2 ),
      "touching UNIVERSAL changed '$class' method availability"
    );
  }

  my $bottom_most_V_D_C_A = refdesc(
    describe_class_methods("DBIx::Class::MethodAttributes")
     ->{methods}
      ->{VALID_DBIC_CODE_ATTRIBUTE}
       ->[0]
  );

  for my $class ( shuffle( qw(
    DBICTest::AttrTest
    DBICTest::AttrLegacy
    DBICTest::SomeGrandParentClass
    DBIx::Class::Schema
    DBIx::Class::ResultSet
    DBICTest::Schema::Track
  ))) {
    my $desc = describe_class_methods($class);

    is (
      refdesc( $desc->{methods}{VALID_DBIC_CODE_ATTRIBUTE}[-1] ),
      $bottom_most_V_D_C_A,
      "Same physical structure returned for last VALID_DBIC_CODE_ATTRIBUTE via class $class"
    );

    is (
      refdesc( $desc->{methods_with_supers}{VALID_DBIC_CODE_ATTRIBUTE}[-1] ),
      $bottom_most_V_D_C_A,
      "Same physical structure returned for bottom-most SUPER of VALID_DBIC_CODE_ATTRIBUTE via class $class"
    ) if $desc->{methods_with_supers}{VALID_DBIC_CODE_ATTRIBUTE};
  }

  # check that describe_class_methods returns the right stuff
  # ( on the simpler class )
  my $expected_AttrTest_ISA = [qw(
    DBICTest::SomeParentClass
    DBICTest::SomeGrandParentClass
    DBICTest::AnotherParentClass
    DBIx::Class::MethodAttributes
  )];

  my $expected_desc = {
    class => "DBICTest::AttrTest",

    # sum and/or is_deeply are buggy on old List::Util/Test::More
    # do the sum by hand ourselves to be sure
    cumulative_gen => do {
      require Math::BigInt;
      my $gen = Math::BigInt->new(0);

      $gen += DBIx::Class::_Util::get_real_pkg_gen($_) for (
        'UNIVERSAL',
        'DBICTest::AttrTest',
        @$expected_AttrTest_ISA,
      );

      $gen;
    },
    mro => {
      type => 'c3',
      is_c3 => 1,
    },
    isa => $expected_AttrTest_ISA,
    methods => {
      FETCH_CODE_ATTRIBUTES => [
        {
          attributes => {},
          name => "FETCH_CODE_ATTRIBUTES",
          via_class => "DBIx::Class::MethodAttributes"
        },
      ],
      MODIFY_CODE_ATTRIBUTES => [
        {
          attributes => {},
          name => "MODIFY_CODE_ATTRIBUTES",
          via_class => "DBIx::Class::MethodAttributes"
        },
      ],
      VALID_DBIC_CODE_ATTRIBUTE => [
        {
          attributes => {},
          name => "VALID_DBIC_CODE_ATTRIBUTE",
          via_class => "DBICTest::SomeGrandParentClass",
        },
        {
          attributes => {},
          name => "VALID_DBIC_CODE_ATTRIBUTE",
          via_class => "DBICTest::AnotherParentClass"
        },
        {
          attributes => {},
          name => "VALID_DBIC_CODE_ATTRIBUTE",
          via_class => "DBIx::Class::MethodAttributes"
        },
      ],
      _attr_cache => [
        {
          attributes => {},
          name => "_attr_cache",
          via_class => "DBIx::Class::MethodAttributes"
        },
      ],
      attr => [
        {
          attributes => {
            DBIC_attr1 => 1,
            DBIC_attr2 => 1,
            DBIC_attr3 => 1,
            lvalue => 1,
            method => 1
          },
          name => "attr",
          via_class => "DBICTest::AttrTest"
        }
      ],
      can => [
        {
          attributes => {},
          name => "can",
          via_class => "UNIVERSAL",
        },
      ],
      isa => [
        {
          attributes => {},
          name => "isa",
          via_class => "UNIVERSAL",
        },
      ],
      VERSION => [
        {
          attributes => {},
          name => "VERSION",
          via_class => "UNIVERSAL",
        },
      ],
      ( DBIx::Class::_ENV_::OLD_MRO ? () : (
        DOES => [{
          attributes => {},
          name => "DOES",
          via_class => "UNIVERSAL",
        }],
      ) ),
    },
  };

  $expected_desc->{methods_with_supers}{VALID_DBIC_CODE_ATTRIBUTE}
    = $expected_desc->{methods}{VALID_DBIC_CODE_ATTRIBUTE};

  $expected_desc->{methods_defined_in_class}{attr}
    = $expected_desc->{methods}{attr}[0];

  is_deeply (
    describe_class_methods("DBICTest::AttrTest"),
    $expected_desc,
    'describe_class_methods returns correct data',
  );
}

if ($skip_threads) {
  SKIP: { skip "Skipping the thread test: $skip_threads", 1 }

  add_more_attrs();
}
else { SKIP: {

  my $t = threads->create(sub {

    my $t = threads->create(sub {

      add_more_attrs();
      select( undef, undef, undef, 0.2 ); # without this many tasty crashes even on latest perls

      42;

    }) || do {
      die "Unable to start thread: $!"
        unless $! == Errno::EAGAIN();

      SKIP: { skip "EAGAIN encountered, your system is likely bogged down: skipping rest of test", 1 }

      return 42 ;
    };

    my $rv = $t->join;

    select( undef, undef, undef, 0.2 ); # without this many tasty crashes even on latest perls

    $rv;
  }) || do {
    die "Unable to start thread: $!"
      unless $! == Errno::EAGAIN();

    skip "EAGAIN encountered, your system is likely bogged down: skipping rest of test", 1;
  };

  is (
    $t->join,
    42,
    'Thread stack exitted succesfully'
  );
}}

# this doesn't really belong in this test, but screw it
{
  package DBICTest::WackyDFS;
  use base qw( DBICTest::SomeGrandParentClass DBICTest::SomeParentClass );
}

is_deeply
  describe_class_methods("DBICTest::WackyDFS")->{methods}{VALID_DBIC_CODE_ATTRIBUTE},
  [
    {
      attributes => {},
      name => "VALID_DBIC_CODE_ATTRIBUTE",
      via_class => "DBICTest::SomeGrandParentClass",
    },
    {
      attributes => {},
      name => "VALID_DBIC_CODE_ATTRIBUTE",
      via_class => "DBIx::Class::MethodAttributes"
    },
  ],
  'Expected description on unusable inheritance hierarchy'
;

done_testing;
