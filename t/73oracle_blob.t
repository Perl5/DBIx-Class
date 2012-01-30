use strict;
use warnings;

use Test::Exception;
use Test::More;
use Sub::Name;
use Try::Tiny;
use DBIx::Class::Optional::Dependencies ();

use lib qw(t/lib);

# add extra columns for the bindtype tests
BEGIN {
  require DBICTest::RunMode;
  require DBICTest::Schema::BindType;
  DBICTest::Schema::BindType->add_columns(
    'blob2' => {
      data_type => 'blob',
      is_nullable => 1,
    },
    'clob2' => {
      data_type => 'clob',
      is_nullable => 1,
    },
  );
}

use DBICTest;
use DBIC::SqlMakerTest;

my ($dsn,  $user,  $pass)  = @ENV{map { "DBICTEST_ORA_${_}" }  qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_ORA_DSN}, _USER and _PASS to run this test.'
  unless ($dsn && $user && $pass);

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_rdbms_oracle')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_rdbms_oracle');

$ENV{NLS_SORT} = "BINARY";
$ENV{NLS_COMP} = "BINARY";
$ENV{NLS_LANG} = "AMERICAN";

my $v = do {
  my $si = DBICTest::Schema->connect($dsn, $user, $pass)->storage->_server_info;
  $si->{normalized_dbms_version}
    or die "Unparseable Oracle server version: $si->{dbms_version}\n";
};

##########
# the recyclebin (new for 10g) sometimes comes in the way
my $on_connect_sql = $v >= 10 ? ["ALTER SESSION SET recyclebin = OFF"] : [];

# iterate all tests on following options
my @tryopt = (
  { on_connect_do => $on_connect_sql },
  { quote_char => '"', on_connect_do => $on_connect_sql },
);

# keep a database handle open for cleanup
my $dbh;

my $schema;
for my $opt (@tryopt) {
  my $schema = DBICTest::Schema->connect($dsn, $user, $pass, $opt);

  $dbh = $schema->storage->dbh;
  my $q = $schema->storage->sql_maker->quote_char || '';

  do_creates($dbh, $q);

  _run_tests($schema, $opt);
}

sub _run_tests {
  my ($schema, $opt) = @_;

  my $q = $schema->storage->sql_maker->quote_char || '';

  my %binstr = ( 'small' => join('', map { chr($_) } ( 1 .. 127 )) );
  $binstr{'large'} = $binstr{'small'} x 1024;

  my $maxloblen = (length $binstr{'large'}) + 6;
  note "Localizing LongReadLen to $maxloblen to avoid truncation of test data";
  local $dbh->{'LongReadLen'} = $maxloblen;

  my $rs = $schema->resultset('BindType');

  # disable BLOB mega-output
  my $orig_debug = $schema->storage->debug;

  my $id;
  foreach my $size (qw( small large )) {
    $id++;

    if ($size eq 'small') {
      $schema->storage->debug($orig_debug);
    }
    elsif ($size eq 'large') {
      $schema->storage->debug(0);
    }

    my $str = $binstr{$size};
    lives_ok {
      $rs->create( { 'id' => $id, blob => "blob:$str", blob2 => "blob2:$str", clob => "clob:$str", clob2 => "clob2:$str" } )
    } "inserted $size without dying";

    my %kids = %{$schema->storage->_dbh->{CachedKids}};
    my @objs = $rs->search({ blob => "blob:$str", blob2 => "blob2:$str", clob => "clob:$str", clob2 => "clob2:$str" })->all;
    is_deeply (
      $schema->storage->_dbh->{CachedKids},
      \%kids,
      'multi-part LOB equality query was not cached',
    ) if $size eq 'large';
    is @objs, 1, 'One row found matching on both LOBs';
    ok (try { $objs[0]->blob }||'' eq "blob:$str", 'blob inserted/retrieved correctly');
    ok (try { $objs[0]->blob2 }||'' eq "blob2:$str", 'blob2 inserted/retrieved correctly');
    ok (try { $objs[0]->clob }||'' eq "clob:$str", 'clob inserted/retrieved correctly');
    ok (try { $objs[0]->clob2 }||'' eq "clob2:$str", 'clob2 inserted/retrieved correctly');

    $rs->find($id)->delete;

    lives_ok {
      $rs->populate( [ { 'id' => $id, blob => "blob:$str", blob2 => "blob2:$str", clob => "clob:$str", clob2 => "clob2:$str" } ] )
    } "inserted $size via insert_bulk without dying";

    @objs = $rs->search({ blob => "blob:$str", blob2 => "blob2:$str", clob => "clob:$str", clob2 => "clob2:$str" })->all;
    is @objs, 1, 'One row found matching on both LOBs';
    ok (try { $objs[0]->blob }||'' eq "blob:$str", 'blob inserted/retrieved correctly');
    ok (try { $objs[0]->blob2 }||'' eq "blob2:$str", 'blob2 inserted/retrieved correctly');
    ok (try { $objs[0]->clob }||'' eq "clob:$str", 'clob inserted/retrieved correctly');
    ok (try { $objs[0]->clob2 }||'' eq "clob2:$str", 'clob2 inserted/retrieved correctly');

    TODO: {
      local $TODO = '-like comparison on blobs not tested before ora 10 (fails on 8i)'
        if $schema->storage->_server_info->{normalized_dbms_version} < 10;

      lives_ok {
        @objs = $rs->search({ clob => { -like => 'clob:%' } })->all;
        ok (@objs, 'rows found matching CLOB with a LIKE query');
      } 'Query with like on blob succeeds';
    }

    ok(my $subq = $rs->search(
      { blob => "blob:$str", blob2 => "blob2:$str", clob => "clob:$str", clob2 => "clob2:$str" },
      {
        from => \ "(SELECT * FROM ${q}bindtype_test${q} WHERE ${q}id${q} != ?) ${q}me${q}",
        bind => [ [ undef => 12345678 ] ],
      }
    )->get_column('id')->as_query);

    @objs = $rs->search({ id => { -in => $subq } })->all;
    is (@objs, 1, 'One row found matching on both LOBs as a subquery');

    lives_ok {
      $rs->search({ id => $id, blob => "blob:$str", blob2 => "blob2:$str", clob => "clob:$str", clob2 => "clob2:$str" })
        ->update({ id => 9999 });
    } 'blob UPDATE with blobs in WHERE clause survived';

    @objs = $rs->search({ id => 9999, blob => "blob:$str", blob2 => "blob2:$str", clob => "clob:$str", clob2 => "clob2:$str" })->all;
    is @objs, 1, 'found updated row';

    lives_ok {
      $rs->search({ id => 9999 })->update({ blob => 'updated blob', blob2 => 'updated blob2', clob => 'updated clob', clob2 => 'updated clob2' });
    } 'blob UPDATE survived';

    @objs = $rs->search({ blob => "updated blob", blob2 => "updated blob2", clob => 'updated clob', clob2 => 'updated clob2' })->all;
    is @objs, 1, 'found updated row';
    ok (try { $objs[0]->blob }||'' eq "updated blob", 'blob updated/retrieved correctly');
    ok (try { $objs[0]->blob2 }||'' eq "updated blob2", 'blob2 updated/retrieved correctly');
    ok (try { $objs[0]->clob }||'' eq "updated clob", 'clob updated/retrieved correctly');
    ok (try { $objs[0]->clob2 }||'' eq "updated clob2", 'clob2 updated/retrieved correctly');

    # test multirow update
    $rs->create({ id => $id+1, blob => 'updated blob', blob2 => 'updated blob2', clob => 'updated clob', clob2 => 'updated clob2' });

    lives_ok {
      $rs->search({ id => [ 9999, $id+1 ], blob => 'updated blob', blob2 => 'updated blob2', clob => 'updated clob', clob2 => 'updated clob2' })->update({ blob => 'updated blob again', blob2 => 'updated blob2 again', clob => 'updated clob again', clob2 => 'updated clob2 again' });
    } 'lob multirow UPDATE based on lobs in WHERE clause survived';

    @objs = $rs->search({ blob => "updated blob again", blob2 => "updated blob2 again", clob => 'updated clob again', clob2 => 'updated clob2 again' })->all;
    is @objs, 2, 'found updated rows';
    foreach my $idx (0..1) {
      ok (try { $objs[$idx]->blob }||'' eq "updated blob again", 'blob updated/retrieved correctly');
      ok (try { $objs[$idx]->blob2 }||'' eq "updated blob2 again", 'blob2 updated/retrieved correctly');
      ok (try { $objs[$idx]->clob }||'' eq "updated clob again", 'clob updated/retrieved correctly');
      ok (try { $objs[$idx]->clob2 }||'' eq "updated clob2 again", 'clob2 updated/retrieved correctly');
    }

    $rs->find($id+1)->delete;
    $rs->find(9999)->update({ id => $id });

    lives_ok {
      $rs->search({ id => $id  })
        ->update({ blob => 're-updated blob', blob2 => 're-updated blob2', clob => 're-updated clob', clob2 => 're-updated clob2' });
    } 'blob UPDATE without blobs in WHERE clause survived';

    @objs = $rs->search({ blob => 're-updated blob', blob2 => 're-updated blob2', clob => 're-updated clob', clob2 => 're-updated clob2' })->all;
    is @objs, 1, 'found updated row';
    ok (try { $objs[0]->blob }||'' eq 're-updated blob', 'blob updated/retrieved correctly');
    ok (try { $objs[0]->blob2 }||'' eq 're-updated blob', 'blob2 updated/retrieved correctly');
    ok (try { $objs[0]->clob }||'' eq 're-updated clob', 'clob updated/retrieved correctly');
    ok (try { $objs[0]->clob2 }||'' eq 're-updated clob2', 'clob2 updated/retrieved correctly');

    lives_ok {
      $rs->search({ blob => "re-updated blob", blob2 => "re-updated blob2", clob => "re-updated clob", clob2 => "re-updated clob2" })
        ->delete;
    } 'blob DELETE with WHERE clause survived';
    @objs = $rs->search({ blob => "re-updated blob", blob2 => "re-updated blob2", clob => 're-updated clob', clob2 => 're-updated clob2' })->all;
    is @objs, 0, 'row deleted successfully';
  }

  $schema->storage->debug ($orig_debug);

  do_clean ($dbh);
}

done_testing;

sub do_creates {
  my ($dbh, $q) = @_;

  do_clean($dbh);

  $dbh->do("CREATE TABLE ${q}bindtype_test${q} (${q}id${q} integer NOT NULL PRIMARY KEY, ${q}bytea${q} integer NULL, ${q}blob${q} blob NULL, ${q}blob2${q} blob NULL, ${q}clob${q} clob NULL, ${q}clob2${q} clob NULL, ${q}a_memo${q} integer NULL)");
}

# clean up our mess
sub do_clean {

  my $dbh = shift || return;

  for my $q ('', '"') {
    my @clean = (
      "DROP TABLE ${q}bindtype_test${q}",
    );
    eval { $dbh -> do ($_) } for @clean;
  }
}

END {
  if ($dbh) {
    local $SIG{__WARN__} = sub {};
    do_clean($dbh);
    undef $dbh;
  }
}
