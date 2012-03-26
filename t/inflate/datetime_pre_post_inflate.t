use strict;
use warnings;

use Test::More;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;

# so user's env doesn't screw us
delete $ENV{DBIC_DT_SEARCH_OK};

my $schema = DBICTest->init_schema();

plan skip_all => 'DT inflation tests need ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_dt_sqlite')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_dt_sqlite');

my $event_rs = $schema->resultset("EventPrePostInflate");
my $event = $event_rs->new({});

can_ok $event, qw/_post_inflate_datetime _pre_deflate_datetime post_inflate_datetime pre_deflate_datetime/;

warning_like {
    $event_rs->create({ starts_at => DateTime->now(time_zone => 'UTC') });
} qr/deprecated/, 'Get warning for overloading _pre_deflate_datetime.';

warning_like {
    $event_rs->find(1)->starts_at;
} qr/deprecated/, 'Get warning for overloading _post_inflate_datetime.';

done_testing;
