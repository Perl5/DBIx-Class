use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

{ # Fake storage driver for sqlite with autocast
    package DBICTest::SQLite::AutoCast;
    use base qw/
        DBIx::Class::Storage::DBI::AutoCast
        DBIx::Class::Storage::DBI::SQLite
    /;
    use mro 'c3';

    my $type_map = {
      datetime => 'DateTime',
      integer => 'INT',
      int => undef, # no conversion
    };

    sub _native_data_type {
      return $type_map->{$_[1]};
    }
}

my $schema = DBICTest->init_schema (storage_type => 'DBICTest::SQLite::AutoCast');

# 'me.id' will be cast unlike the unqualified 'id'
my $rs = $schema->resultset ('CD')->search ({
  cdid => { '>', 5 },
  'tracks.last_updated_at' => { '!=', undef },
  'tracks.last_updated_on' => { '<', 2009 },
  'tracks.position' => 4,
  'me.single_track' => \[ '= ?', [ single_track => 1 ] ],
}, { join => 'tracks' });

my ($sql, @bind);
my $debugobj = DBIC::DebugObj->new (\$sql, \@bind);
my $storage = $schema->storage;
my ($orig_debug, $orig_debugobj) = ($storage->debug, $storage->debugobj);
$storage->debugobj ($debugobj);
$storage->debug (1);

# the quoting is a debugobj thing, not dbic-internals
my $bind = [ map { "'$_'" } qw/
  5 1 2009 4
/];

$rs->all;
is_same_sql_bind (
  $sql,
  \@bind,
  '
    SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track
      FROM cd me
      LEFT JOIN track tracks ON tracks.cd = me.cdid
    WHERE
          cdid > ?
      AND me.single_track = ?
      AND tracks.last_updated_at IS NOT NULL
      AND tracks.last_updated_on < ?
      AND tracks.position = ?
  ',
  $bind,
  'expected sql with casting off',
);

$schema->storage->auto_cast (1);

$rs->all;
is_same_sql_bind (
  $sql,
  \@bind,
  '
    SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track
      FROM cd me
      LEFT JOIN track tracks ON tracks.cd = me.cdid
    WHERE
          cdid > CAST(? AS INT)
      AND me.single_track = CAST(? AS INT)
      AND tracks.last_updated_at IS NOT NULL
      AND tracks.last_updated_on < CAST (? AS DateTime)
      AND tracks.position = ?
  ',
  $bind,
  'expected sql with casting on',
);

$storage->debugobj ($orig_debugobj);
$storage->debug ($orig_debug);

done_testing;
