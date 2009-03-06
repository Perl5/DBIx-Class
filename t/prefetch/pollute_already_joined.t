use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Data::Dumper;

my $schema = DBICTest->init_schema();

my $orig_debug = $schema->storage->debug;

use IO::File;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 10 );
}

# figure out if we've got a version of sqlite that is older than 3.2.6, in
# which case COUNT(DISTINCT()) doesn't work
my $is_broken_sqlite = 0;
my ($sqlite_major_ver,$sqlite_minor_ver,$sqlite_patch_ver) =
    split /\./, $schema->storage->dbh->get_info(18);
if( $schema->storage->dbh->get_info(17) eq 'SQLite' &&
    ( ($sqlite_major_ver < 3) ||
      ($sqlite_major_ver == 3 && $sqlite_minor_ver < 2) ||
      ($sqlite_major_ver == 3 && $sqlite_minor_ver == 2 && $sqlite_patch_ver < 6) ) ) {
    $is_broken_sqlite = 1;
}

# A search() with prefetch seems to pollute an already joined resultset
# in a way that offsets future joins (adapted from a test case by Debolaz)
{
  my ($cd_rs, $attrs);

  # test a real-life case - rs is obtained by an implicit m2m join
  $cd_rs = $schema->resultset ('Producer')->first->cds;
  $attrs = Dumper $cd_rs->{attrs};

  $cd_rs->search ({})->all;
  is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after a simple search');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after search with prefetch');
  }, 'first prefetching search ok');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after another search with prefetch')
  }, 'second prefetching search ok');


  # test a regular rs with an empty seen_join injected - it should still work!
  $cd_rs = $schema->resultset ('CD');
  $cd_rs->{attrs}{seen_join}  = {};
  $attrs = Dumper $cd_rs->{attrs};

  $cd_rs->search ({})->all;
  is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after a simple search');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after search with prefetch');
  }, 'first prefetching search ok');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after another search with prefetch')
  }, 'second prefetching search ok');
}
