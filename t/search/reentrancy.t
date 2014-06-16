use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $track_titles = { map { @$_ }
  $schema->resultset('Track')
          ->search({}, { columns => [qw(trackid title)] })
           ->cursor
            ->all
};

my $rs = $schema->resultset('Track');

for my $pass (1,2,3) {
  for my $meth (qw(search single find)) {

    my $id = (keys %$track_titles)[0];
    my $tit = delete $track_titles->{$id};

    my ($o) = $rs->$meth({ trackid => $id });

    is(
      $rs->count({ trackid => $id }),
      1,
      "Count works (pass $pass)",
    );

    is(
      $o->title,
      $tit,
      "Correct object retrieved via $meth() (pass $pass)"
    );

    $o->delete;

    is(
      $rs->count_rs({ trackid => $id })->next,
      0,
      "Count_rs works (pass $pass)",
    );
  }
}

done_testing;
