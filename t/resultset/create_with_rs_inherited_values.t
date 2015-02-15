use strict;
use warnings;

use Test::More;
use Test::Exception;
use Math::BigInt;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();
my $artist_rs = $schema->resultset('Artist');
my $cd_rs = $schema->resultset('CD');

 {
   my $cd;
   lives_ok {
     $cd = $cd_rs->search({ year => {'=' => 1999}})->create
       ({
         artist => {name => 'Guillermo1'},
         title => 'Guillermo 1',
        });
   };
   is($cd->year, 1999);
 }

 {
   my $dt = Math::BigInt->new(2006);

   my $cd;
   lives_ok {
     $cd = $cd_rs->search({ year => $dt})->create
       ({
         artist => {name => 'Guillermo2'},
         title => 'Guillermo 2',
        });
   };
   is($cd->year, 2006);
 }


{
  my $artist;
  lives_ok {
    $artist = $artist_rs->search({ name => {'!=' => 'Killer'}})
      ->create({artistid => undef});
  };
  is($artist->name, undef);
}


{
  my $artist;
  lives_ok {
    $artist = $artist_rs->search({ name => [ qw(some stupid names here) ]})
      ->create({artistid => undef});
  };
  is($artist->name, undef);
}

done_testing;
