use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $no_class = '_DBICTEST_NONEXISTENT_CLASS_';

my $schema = DBICTest->init_schema();
$schema->storage->datetime_parser_type($no_class);

my $event = $schema->resultset('Event')->find(1);

# test that datetime_undef_if_invalid does not eat the missing dep exception
throws_ok {
  my $dt = $event->starts_at;
} qr{Can't locate ${no_class}\.pm};

done_testing;
