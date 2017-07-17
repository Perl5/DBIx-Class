use warnings;
use strict;

use Config;
BEGIN {
  my $skipall;

  if( ! $Config{useithreads} ) {
    $skipall = 'your perl does not support ithreads';
  }
  elsif( "$]" < 5.008005 ) {
    $skipall = 'DBIC does not actively support threads before perl 5.8.5';
  }
  elsif( $INC{'Devel/Cover.pm'} ) {
    $skipall = 'Devel::Cover does not work with ithreads yet';
  }

  if( $skipall ) {
    print "1..0 # SKIP $skipall\n";
    exit 0;
  }
}

use threads;
use Test::More;
use DBIx::Class::_Util 'hrefaddr';
use Scalar::Util 'weaken';

{
  package DBICTest::Ancestry::Result;

  use base 'DBIx::Class::Core';

  __PACKAGE__->table("foo");
}

{
  package DBICTest::Ancestry::Schema;

  use base 'DBIx::Class::Schema';

  __PACKAGE__->register_class( r => "DBICTest::Ancestry::Result" );
}

my $schema = DBICTest::Ancestry::Schema->clone;
my $rsrc = $schema->resultset("r")->result_source->clone;

threads->new( sub {

  my $another_rsrc = $rsrc->clone;

  is_deeply
    refaddrify( DBICTest::Ancestry::Result->result_source_instance->__derived_instances ),
    refaddrify(
      DBICTest::Ancestry::Schema->source("r"),
      $schema->source("r"),
      $rsrc,
      $another_rsrc,
    )
  ;

  undef $schema;
  undef $rsrc;
  $another_rsrc->schema(undef);

  is_deeply
    refaddrify( DBICTest::Ancestry::Result->result_source_instance->__derived_instances ),
    refaddrify(
      DBICTest::Ancestry::Schema->source("r"),
      $another_rsrc,
    )
  ;

  # tasty crashes without this
  select( undef, undef, undef, 0.2 );
})->join;

sub refaddrify {
  [ sort map { hrefaddr $_ } @_ ];
}

done_testing;
