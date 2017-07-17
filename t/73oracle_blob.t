BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => 'test_rdbms_oracle';

use strict;
use warnings;

use Test::Exception;
use Test::More;

use DBICTest::Schema::BindType;
BEGIN {
  DBICTest::Schema::BindType->add_columns(
    'blb2' => {
      data_type => 'blob',
      is_nullable => 1,
    },
    'clb2' => {
      data_type => 'clob',
      is_nullable => 1,
    }
  );
}

use DBICTest;

$ENV{NLS_SORT} = "BINARY";
$ENV{NLS_COMP} = "BINARY";
$ENV{NLS_LANG} = "AMERICAN";

my ($dsn,  $user,  $pass)  = @ENV{map { "DBICTEST_ORA_${_}" }  qw/DSN USER PASS/};

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

  _run_blob_tests($schema, $opt);
}

sub _run_blob_tests {
SKIP: {
  my ($schema, $opt) = @_;
  my %binstr = ( 'small' => join('', map { chr($_) } ( 1 .. 127 )) );
  $binstr{'large'} = $binstr{'small'} x 1024;

  my $maxloblen = (length $binstr{'large'}) + 5;
  note "Localizing LongReadLen to $maxloblen to avoid truncation of test data";
  local $dbh->{'LongReadLen'} = $maxloblen;

  my $rs = $schema->resultset('BindType');

  if ($DBD::Oracle::VERSION eq '1.23') {
    throws_ok { $rs->create({ id => 1, blob => $binstr{large} }) }
      qr/broken/,
      'throws on blob insert with DBD::Oracle == 1.23';
    skip 'buggy BLOB support in DBD::Oracle 1.23', 1;
  }

  my $q = $schema->storage->sql_maker->quote_char || '';
  local $TODO = 'Something is confusing column bindtype assignment when quotes are active'
              . ': https://rt.cpan.org/Ticket/Display.html?id=64206'
    if $q;

  my $id;
  foreach my $size (qw( small large )) {
    $id++;

    local $schema->storage->{debug} = 0
      if $size eq 'large';

    my $str = $binstr{$size};
    lives_ok {
      $rs->create( { 'id' => $id, blob => "blob:$str", clob => "clob:$str", blb2 => "blb2:$str", clb2 => "clb2:$str" } )
    } "inserted $size without dying";

    my %kids = %{$schema->storage->_dbh->{CachedKids}};
    my @objs = $rs->search({ blob => "blob:$str", clob => "clob:$str" })->all;
    is_deeply (
      $schema->storage->_dbh->{CachedKids},
      \%kids,
      'multi-part LOB equality query was not cached',
    ) if $size eq 'large';
    is @objs, 1, 'One row found matching on both LOBs';

    for my $type (qw( blob clob clb2 blb2 )) {
      is (
        eval { $objs[0]->$type },
        "$type:$str",
        "$type inserted/retrieved correctly"
      );
    }

    {
      local $TODO = '-like comparison on blobs not tested before ora 10 (fails on 8i)'
        if $schema->storage->_server_info->{normalized_dbms_version} < 10;

      lives_ok {
        @objs = $rs->search({ clob => { -like => 'clob:%' } })->all;
        ok (@objs, 'rows found matching CLOB with a LIKE query');
      } 'Query with like on blob succeeds';
    }

    ok(my $subq = $rs->search(
      { blob => "blob:$str", clob => "clob:$str" },
      {
        from => \ "(SELECT * FROM ${q}bindtype_test${q} WHERE ${q}id${q} != ?) ${q}me${q}",
        bind => [ [ {} => 12345678 ] ],
      }
    )->get_column('id')->as_query);

    @objs = $rs->search({ id => { -in => $subq } })->all;
    is (@objs, 1, 'One row found matching on both LOBs as a subquery');

    lives_ok {
      $rs->search({ id => $id, blob => "blob:$str", clob => "clob:$str" })
        ->update({ blob => 'updated blob', clob => 'updated clob', clb2 => 'updated clb2', blb2 => 'updated blb2' });
    } 'blob UPDATE with blobs in WHERE clause survived';

    @objs = $rs->search({ blob => "updated blob", clob => 'updated clob' })->all;
    is @objs, 1, 'found updated row';

    for my $type (qw( blob clob clb2 blb2 )) {
      is (
        eval { $objs[0]->$type },
        "updated $type",
        "$type updated/retrieved correctly"
      );
    }

    lives_ok {
      $rs->search({ id => $id  })
        ->update({ blob => 're-updated blob', clob => 're-updated clob' });
    } 'blob UPDATE without blobs in WHERE clause survived';

    @objs = $rs->search({ blob => 're-updated blob', clob => 're-updated clob' })->all;
    is @objs, 1, 'found updated row';

    for my $type (qw( blob clob )) {
      is (
        eval { $objs[0]->$type },
        "re-updated $type",
        "$type updated/retrieved correctly"
      );
    }

    lives_ok {
      $rs->search({ blob => "re-updated blob", clob => "re-updated clob" })
        ->delete;
    } 'blob DELETE with WHERE clause survived';
    @objs = $rs->search({ blob => "re-updated blob", clob => 're-updated clob' })->all;
    is @objs, 0, 'row deleted successfully';
  }
}

  do_clean ($dbh);
}

done_testing;

sub do_creates {
  my ($dbh, $q) = @_;

  do_clean($dbh);

  $dbh->do("CREATE TABLE ${q}bindtype_test${q} (${q}id${q} integer NOT NULL PRIMARY KEY, ${q}bytea${q} integer NULL, ${q}blob${q} blob NULL, ${q}blb2${q} blob NULL, ${q}clob${q} clob NULL, ${q}clb2${q} clob NULL, ${q}a_memo${q} integer NULL)");
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
