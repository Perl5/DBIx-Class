use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

{
  my $cd_rc = $schema->resultset("CD")->result_class;

  throws_ok {
    $schema->resultset("Artist")
      ->search_rs({}, {result_class => "IWillExplode"})
  } qr/Can't locate IWillExplode/, 'nonexistant result_class exception';

# to make ensure_class_loaded happy, dies on inflate
  eval 'package IWillExplode; sub dummy {}';

  my $artist_rs = $schema->resultset("Artist")
    ->search_rs({}, {result_class => "IWillExplode"});
  is($artist_rs->result_class, 'IWillExplode', 'Correct artist result_class');

  throws_ok {
    $artist_rs->result_class('mtfnpy')
  } qr/Can't locate mtfnpy/,
  'nonexistant result_access exception (from accessor)';

  throws_ok {
    $artist_rs->first
  } qr/\QInflator IWillExplode does not provide an inflate_result() method/,
  'IWillExplode explodes on inflate';

  my $cd_rs = $artist_rs->related_resultset('cds');
  is($cd_rs->result_class, $cd_rc, 'Correct cd result_class');

  my $cd_rs2 = $schema->resultset("Artist")->search_rs({})->related_resultset('cds');
  is($cd_rs->result_class, $cd_rc, 'Correct cd2 result_class');

  my $cd_rs3 = $schema->resultset("Artist")->search_rs({},{})->related_resultset('cds');
  is($cd_rs->result_class, $cd_rc, 'Correct cd3 result_class');

  isa_ok(eval{ $cd_rs->find(1) }, $cd_rc, 'Inflated into correct cd result_class');
}


{
  my $cd_rc = $schema->resultset("CD")->result_class;

  my $artist_rs = $schema->resultset("Artist")
    ->search_rs({}, {result_class => "IWillExplode"})->search({artistid => 1});
  is($artist_rs->result_class, 'IWillExplode', 'Correct artist result_class');

  my $cd_rs = $artist_rs->related_resultset('cds');
  is($cd_rs->result_class, $cd_rc, 'Correct cd result_class');

  isa_ok(eval{ $cd_rs->find(1) }, $cd_rc, 'Inflated into correct cd result_class');
  isa_ok(eval{ $cd_rs->search({ cdid => 1 })->first }, $cd_rc, 'Inflated into correct cd result_class');
}

{
  my $rs = $schema->resultset('Artist')->search(
    { 'cds.title' => 'Spoonful of bees' },
    { prefetch => 'cds', result_class => 'DBIx::Class::ResultClass::HashRefInflator' },
  );

  is ($rs->result_class, 'DBIx::Class::ResultClass::HashRefInflator', 'starting with correct resultclass');

  $rs->result_class('DBICTest::Artist');
  is ($rs->result_class, 'DBICTest::Artist', 'resultclass changed');

  my $art = $rs->next;
  is (ref $art, 'DBICTest::Artist', 'Correcty blessed output');

  throws_ok
    { $rs->result_class('IWillExplode') }
    qr/\QChanging the result_class of a ResultSet instance with an active cursor is not supported/,
    'Throws on result class change in progress'
  ;

  my $cds = $art->cds;

  warnings_exist
    { $cds->result_class('IWillExplode') }
    qr/\QChanging the result_class of a ResultSet instance with cached results is a noop/,
    'Warning on noop result_class change'
  ;

  is ($cds->result_class, 'IWillExplode', 'class changed anyway');

  # even though the original was HRI (at $rs definition time above)
  # we lost the control over the *prefetched* object result class
  # when we handed the root object creation to ::Row::inflate_result
  is( ref $cds->next, 'DBICTest::CD', 'Correctly inflated prefetched result');
}

done_testing;
