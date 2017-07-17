BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

# things will die if this is set
BEGIN { $ENV{DBIC_ASSERT_NO_ERRONEOUS_METAINSTANCE_USE} = 0 }

use strict;
use warnings;

use Test::More;

use DBICTest::Util 'capture_stderr';
use DBICTest;

my ($fn) = __FILE__ =~ /( [^\/\\]+ ) $/x;
my @divergence_lines;

my $art = DBICTest->init_schema->resultset("Artist")->find(1);

push @divergence_lines, __LINE__ + 1;
DBICTest::Schema::Artist->add_columns("Something_New");

push @divergence_lines, __LINE__ + 1;
$_->add_column("Something_New_2") for grep
  { $_ != $art->result_source }
  DBICTest::Schema::Artist->result_source_instance->__derived_instances
;

push @divergence_lines, __LINE__ + 1;
DBICTest::Schema::Artist->result_source_instance->name("foo");

my $orig_class_rsrc_before_table_triggered_reinit = DBICTest::Schema::Artist->result_source_instance;

push @divergence_lines, __LINE__ + 1;
DBICTest::Schema::Artist->table("bar");

is(
  capture_stderr {
    ok(
      DBICTest::Schema::Artist->has_column( "Something_New" ),
      'Added column visible'
    );

    ok(
      (! DBICTest::Schema::Artist->has_column( "Something_New_2" ) ),
      'Column added on children not visible'
    );
  },
  '',
  'No StdErr output during rsrc augmentation'
);

my $err = capture_stderr {
  ok(
    ! $art->has_column($_),
    "Column '$_' not visible on @{[ $art->table ]}"
  ) for qw(Something_New Something_New_2);
};

# Tricky text - check it painstakingly as things may go off
# in very subtle ways
my $expected_warning_1 = join '.+?', map { quotemeta $_ }
  "@{[ $art->result_source ]} (the metadata instance of source 'Artist') is *OUTDATED*",

  "${orig_class_rsrc_before_table_triggered_reinit}->add_columns(...) at",
    "$fn line $divergence_lines[0]",

  "@{[ DBICTest::Schema->source('Artist') ]}->add_column(...) at",
    "$fn line $divergence_lines[1]",

  "Stale metadata accessed by 'getter' @{[ $art->result_source ]}->has_column(...)",
;

like
  $err,
  qr/$expected_warning_1/s,
  'Correct warning on diverged metadata'
;

my $expected_warning_2 = join '.+?', map { quotemeta $_ }
  "@{[ $art->result_source ]} (the metadata instance of source 'Artist') is *OUTDATED*",

  "${orig_class_rsrc_before_table_triggered_reinit}->name(...) at",
    "$fn line $divergence_lines[2]",

  "${orig_class_rsrc_before_table_triggered_reinit}->table(...) at",
    "$fn line $divergence_lines[3]",

  "Stale metadata accessed by 'getter' @{[ $art->result_source ]}->table(...)",
;

like
  $err,
  qr/$expected_warning_2/s,
  'Correct warning on diverged metadata'
;

done_testing;
