use strict;
use warnings;

use Test::More;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;

{
  package A::Comp;
  use base 'DBIx::Class';
  sub store_column { shift->next::method (@_) };
  1;
}

{
  package A::SubComp;
  use base 'A::Comp';

  1;
}

warnings_are (
  sub {
    package A::Test1;
    use base 'DBIx::Class::Core';
    __PACKAGE__->load_components(qw(Core +A::Comp Ordered UTF8Columns));
    __PACKAGE__->load_components(qw(Ordered +A::SubComp Row UTF8Columns Core));
    sub store_column { shift->next::method (@_) };
    1;
  },
  [],
  'no spurious warnings issued',
);

my $test1_mro;
my $idx = 0;
for (@{mro::get_linear_isa ('A::Test1')} ) {
  $test1_mro->{$_} = $idx++;
}

cmp_ok ($test1_mro->{'A::SubComp'}, '<', $test1_mro->{'A::Comp'}, 'mro of Test1 correct (A::SubComp before A::Comp)' );
cmp_ok ($test1_mro->{'A::Comp'}, '<', $test1_mro->{'DBIx::Class::UTF8Columns'}, 'mro of Test1 correct (A::Comp before UTF8Col)' );
cmp_ok ($test1_mro->{'DBIx::Class::UTF8Columns'}, '<', $test1_mro->{'DBIx::Class::Core'}, 'mro of Test1 correct (UTF8Col before Core)' );
cmp_ok ($test1_mro->{'DBIx::Class::Core'}, '<', $test1_mro->{'DBIx::Class::Row'}, 'mro of Test1 correct (Core before Row)' );

warnings_like (
  sub {
    package A::Test2;
    use base 'DBIx::Class::Core';
    __PACKAGE__->load_components(qw(UTF8Columns +A::Comp));
    sub store_column { shift->next::method (@_) };
    1;
  },
  [qr/Incorrect loading order of DBIx::Class::UTF8Columns.+affect other components overriding 'store_column' \(A::Comp\)/],
  'incorrect order warning issued (violator defines)',
);

warnings_like (
  sub {
    package A::Test3;
    use base 'DBIx::Class::Core';
    __PACKAGE__->load_components(qw(UTF8Columns +A::SubComp));
    sub store_column { shift->next::method (@_) };
    1;
  },
  [qr/Incorrect loading order of DBIx::Class::UTF8Columns.+affect other components overriding 'store_column' \(A::SubComp \(via A::Comp\)\)/],
  'incorrect order warning issued (violator inherits)',
);

my $schema = DBICTest->init_schema();
DBICTest::Schema::CD->load_components('UTF8Columns');
DBICTest::Schema::CD->utf8_columns('title');
Class::C3->reinitialize();

{
  package DBICTest::UTF8::Debugger;

  use base 'DBIx::Class::Storage::Statistics';

  __PACKAGE__->mk_group_accessors(simple => 'call_stack');

  sub query_start {
    my $self = shift;
    my $sql = shift;

    my @bind = map { substr $_, 1, -1 } (@_); # undo the effect of _fix_bind_params

    $self->call_stack ( [ @{$self->call_stack || [] }, [$sql, @bind] ] );
    $self->next::method ($sql, @_);
  }
}

# there's some weird bug in Test::Builder that spews out wide-character warnings
# without any print taking place
$SIG{__WARN__} = sub { warn $_[0] unless $_[0] =~ /Wide character in print/ };

my $bytestream_title = my $utf8_title = "weird \x{466} stuff";
utf8::encode($bytestream_title);
cmp_ok ($bytestream_title, 'ne', $utf8_title, 'unicode/raw differ (sanity check)');

my $storage = $schema->storage;
$storage->debugobj (DBICTest::UTF8::Debugger->new);
$storage->debugobj->silence (1);
$storage->debug (1);

my $cd = $schema->resultset('CD')->create( { artist => 1, title => $utf8_title, year => '2048' } );

# bind values are always alphabetically ordered by column, thus [2]
TODO: {
  local $TODO = "This has been broken since rev 1191, Mar 2006";
  is ($storage->debugobj->call_stack->[-1][2], $bytestream_title, 'INSERT: raw bytes sent to the database');
}

# this should be using the cursor directly, no inflation/processing of any sort
my ($raw_db_title) = $schema->resultset('CD')
                             ->search ($cd->ident_condition)
                               ->get_column('title')
                                ->_resultset
                                 ->cursor
                                  ->next;

is ($raw_db_title, $bytestream_title, 'INSERT: raw bytes retrieved from database');

for my $reloaded (0, 1) {
  my $test = $reloaded ? 'reloaded' : 'stored';
  $cd->discard_changes if $reloaded;

  ok( utf8::is_utf8( $cd->title ), "got $test title with utf8 flag" );
  ok(! utf8::is_utf8( $cd->{_column_data}{title} ), "in-object $test title without utf8" );

  ok(! utf8::is_utf8( $cd->year ), "got $test year without utf8 flag" );
  ok(! utf8::is_utf8( $cd->{_column_data}{year} ), "in-object $test year without utf8" );
}

$cd->title('nonunicode');
ok(! utf8::is_utf8( $cd->title ), 'update title without utf8 flag' );
ok(! utf8::is_utf8( $cd->{_column_data}{title} ), 'store utf8-less title' );

$cd->update;
$cd->discard_changes;
ok(! utf8::is_utf8( $cd->title ), 'reloaded title without utf8 flag' );
ok(! utf8::is_utf8( $cd->{_column_data}{title} ), 'reloaded utf8-less title' );

$bytestream_title = $utf8_title = "something \x{219} else";
utf8::encode($bytestream_title);

$cd->update ({ title => $utf8_title });
is ($storage->debugobj->call_stack->[-1][1], $bytestream_title, 'UPDATE: raw bytes sent to the database');
($raw_db_title) = $schema->resultset('CD')
                             ->search ($cd->ident_condition)
                               ->get_column('title')
                                ->_resultset
                                 ->cursor
                                  ->next;
is ($raw_db_title, $bytestream_title, 'UPDATE: raw bytes retrieved from database');

$cd->discard_changes;
$cd->title($utf8_title);
ok( !$cd->is_column_changed('title'), 'column is not dirty after setting the same unicode value' );

$cd->update ({ title => $utf8_title });
$cd->title('something_else');
ok( $cd->is_column_changed('title'), 'column is dirty after setting to something completely different');

TODO: {
  local $TODO = 'There is currently no way to propagate aliases to inflate_result()';
  $cd = $schema->resultset('CD')->find ({ title => $utf8_title }, { select => 'title', as => 'name' });
  ok (utf8::is_utf8( $cd->get_column ('name') ), 'utf8 flag propagates via as');
}

done_testing;
