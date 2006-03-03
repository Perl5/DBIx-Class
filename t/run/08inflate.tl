sub run_tests {
my $schema = shift;

eval { require DateTime };
plan skip_all => "Need DateTime for inflation tests" if $@;

plan tests => 5;

DBICTest::Schema::CD->inflate_column( 'year',
    { inflate => sub { DateTime->new( year => shift ) },
      deflate => sub { shift->year } }
);
Class::C3->reinitialize;

# inflation test
my $cd = $schema->resultset("CD")->find(3);

is( ref($cd->year), 'DateTime', 'year is a DateTime, ok' );

is( $cd->year->month, 1, 'inflated month ok' );

# deflate test
my $now = DateTime->now;
$cd->year( $now );
$cd->update;

($cd) = $schema->resultset("CD")->search( year => $now->year );
is( $cd->year->year, $now->year, 'deflate ok' );

use YAML;
DBICTest::Schema::Serialized->inflate_column( 'serialized',
    { inflate => sub { Load (shift) },
      deflate => sub { die "Expecting a reference" unless (ref $_[0]); Dump (shift) } }
);
Class::C3->reinitialize;

my $complex1 = {
    id => 1,
    serialized => {
        a => 1,
        b => 2,
    },
};

my $complex2 = {
    id => 1,
    serialized => [qw/a b 1 2/],
};

my $rs = $schema->resultset('Serialized');

my $entry = $rs->create($complex2);

ok($entry->update ($complex1), "update with hashref deflating ok");

ok($entry->update ($complex2), "update with arrayref deflating ok");

}

1;
