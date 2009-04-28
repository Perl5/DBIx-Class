use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

plan tests => 9;

# Set up the "usual" sqlite for DBICTest
my $schema = DBICTest->init_schema;

# Evilness to easily check whether we prepare_cached() or prepare()'d
my ($sth,$new_sth);
my $orig = DBIx::Class::Storage::DBI->can('sth');
local *DBIx::Class::Storage::DBI::sth = sub { my $sth = $orig->(@_); $new_sth = $sth; $sth };

sub cached_ok     { ok($sth == $new_sth, shift) }
sub not_cached_ok { ok($sth != $new_sth, shift) }

$sth = $schema->storage->sth('SELECT 42');

$schema->storage->sth('SELECT 42');
cached_ok('statement caching works');

$schema->storage->disable_sth_caching(1);
$schema->storage->sth('SELECT 42');
not_cached_ok('backward compatibility with disable_sth_caching works');

$schema->storage->prepare_cached(1);
$schema->storage->sth('SELECT 42');
cached_ok('prepare_cached overrides disable_sth_caching');

my $row = $schema->resultset('CD')->first;
$sth = $new_sth;
my $new_row = $schema->resultset('CD')->search(undef,{prepare_cached => 0})->first;
not_cached_ok('disabling prepare_cached in search() works');

$row->title('So long and thanks for all the fish');
$row->update;
$sth = $new_sth;
$new_row->title("Don't Panic");
$new_row->update;
not_cached_ok('disabling prepare_cached in update() works');

$row->delete;
$sth = $new_sth;
$new_row->delete;
not_cached_ok('disabling prepare_cached in delete() works');

$schema->storage->prepare_cached(0);

$row = $schema->resultset('CD')->first;
$sth = $new_sth;
$new_row = $schema->resultset('CD')->search(undef,{prepare_cached => 1})->first;
cached_ok('enabling prepare_cached in search() works');

$row->title('I never got the hang of thursdays');
$row->update;
$sth = $new_sth;
$new_row->title("He's just this guy, you know?");
$new_row->update;
cached_ok('enabling prepare_cached in update() works');

$row->delete;
$sth = $new_sth;
$new_row->delete;
cached_ok('enabling prepare_cached in delete() works');
