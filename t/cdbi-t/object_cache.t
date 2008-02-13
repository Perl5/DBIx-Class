use strict;
use Test::More;
$| = 1;

BEGIN {
  eval "use DBIx::Class::CDBICompat;";
  if ($@) {
    plan (skip_all => 'Class::Trigger and DBIx::ContextualFetch required');
    next;
  }
  eval "use DBD::SQLite";
  plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 5);
}

INIT {
    use lib 't/testlib';
    use Film;
}

ok +Film->create({
    Title       => 'This Is Spinal Tap',
    Director    => 'Rob Reiner',
    Rating      => 'R',
});

{
    my $film1 = Film->retrieve( "This Is Spinal Tap" );
    my $film2 = Film->retrieve( "This Is Spinal Tap" );

    $film1->Director("Marty DiBergi");
    is $film2->Director, "Marty DiBergi", 'retrieve returns the same object';

    $film1->discard_changes;
}

{
    Film->nocache(1);
    
    my $film1 = Film->retrieve( "This Is Spinal Tap" );
    my $film2 = Film->retrieve( "This Is Spinal Tap" );

    $film1->Director("Marty DiBergi");
    is $film2->Director, "Rob Reiner",
       'caching turned off';
    
    $film1->discard_changes;
}

{
    Film->nocache(0);

    my $film1 = Film->retrieve( "This Is Spinal Tap" );
    my $film2 = Film->retrieve( "This Is Spinal Tap" );

    $film1->Director("Marty DiBergi");
    is $film2->Director, "Marty DiBergi",
       'caching back on';

    $film1->discard_changes;
}


{
    Film->nocache(1);

    local $Class::DBI::Weaken_Is_Available = 0;

    my $film1 = Film->retrieve( "This Is Spinal Tap" );
    my $film2 = Film->retrieve( "This Is Spinal Tap" );

    $film1->Director("Marty DiBergi");
    is $film2->Director, "Rob Reiner",
       'CDBI::Weaken_Is_Available turns off all caching';

    $film1->discard_changes;
}
