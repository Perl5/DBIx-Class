use DBIx::Class::Optional::Dependencies -skip_all_without => qw( ic_dt cdbicompat );

use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib 't/cdbi/testlib';

{
    package Thing;

    use base 'DBIC::Test::SQLite';

    Thing->columns(All  => qw[thing_id this that date]);
}

my $thing = Thing->construct({ thing_id => 23, date => "01-02-1994" });
my $date = DateTime->now;
lives_ok {
  $thing->set( date => $date );
  $thing->set( date => $date );
};

$thing->discard_changes;

done_testing;
