BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

$ENV{DBIC_ASSERT_NO_FAILING_SANITY_CHECKS} = 1;

use strict;
use warnings;

use Test::More;

use DBICTest;
use Sub::Quote 'quote_sub';

my $colinfo = DBICTest::Schema::Artist->result_source->column_info('artistid');

my $schema = DBICTest->init_schema ( no_deploy => 1 );
my $rsrc = $schema->source("Artist");

for my $overrides_marked_mandatory (0, 1) {
  my $call_count;
  my @methods_to_override = qw(
    add_columns columns_info
  );

  my $attr = { attributes => [
    $overrides_marked_mandatory
      ? 'DBIC_method_is_mandatory_resultsource_proxy'
      : 'DBIC_method_is_bypassable_resultsource_proxy'
  ] };

  for (@methods_to_override) {
    $call_count->{$_} = 0;

    quote_sub( "DBICTest::Schema::Artist::$_", <<'EOC', { '$cnt' => \\($call_count->{$_}) }, $attr );
      $$cnt++;
      shift->next::method(@_);
EOC
  }

  Class::C3->reinitialize() if DBIx::Class::_ENV_::OLD_MRO;

  is_deeply
    $rsrc->columns_info->{artistid},
    $colinfo,
    'Expected result from rsrc getter',
  ;

  $rsrc->add_columns("bar");

  is_deeply
    $call_count,
    {
      add_columns => ($overrides_marked_mandatory ? 1 : 0),

      # ResultSourceProxy::add_columns will call colinfos as well
      columns_info => ($overrides_marked_mandatory ? 2 : 0),
    },
    'expected rsrc proxy override callcounts',
  ;
}

done_testing;
