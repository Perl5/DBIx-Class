use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DateTime;

use_ok('DBICTest');

my $schema = DBICTest->init_schema();

my %sql_maker = (
   sqlite => $schema->storage->sql_maker,
);

my $date = DateTime->new(
   year => 2010,
   month => 12,
   day   => 14,
   hour  => 12,
   minute => 12,
   second => 12,
);

my $date2 = $date->clone->set_day(16);

my @tests = (
  {
    func   => 'select',
    args   => ['artist', '*', { 'artist.when_began' => { -dt => $date } }],
    sqlite => {
       stmt   => 'SELECT * FROM artist WHERE artist.when_began = ?',
       bind   => [[ 'artist.when_began', '2010-12-14 12:12:12' ]],
    },
    msg => '-dt_now works',
  },
  {
    func   => 'update',
    args   => ['artist',
      { 'artist.when_began' => { -dt => $date } },
      { 'artist.when_ended' => { '<' => { -dt => $date2 } } }
    ],
    sqlite => {
       stmt   => 'UPDATE artist SET artist.when_began = ?  WHERE artist.when_ended < ?  ',
       bind   => [
         [ 'artist.when_began', '2010-12-14 12:12:12' ],
         [ 'artist.when_ended', '2010-12-16 12:12:12' ],
       ],
    },
    msg => '-dt_now works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_year => { -ident => 'artist.when_began' } ] ]],
    sqlite => {
      stmt   => "SELECT STRFTIME('%Y', artist.when_began) FROM artist",
       bind   => [],
    },
    msg    => '-dt_year works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_month => { -ident => 'artist.when_began' } ] ]],
    sqlite => {
      stmt   => "SELECT STRFTIME('%m', artist.when_began) FROM artist",
      bind   => [],
    },
    msg    => '-dt_month works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_day => { -ident => 'artist.when_began' } ] ]],
    sqlite => {
      stmt   => "SELECT STRFTIME('%d', artist.when_began) FROM artist",
      bind   => [],
    },
    msg    => '-dt_day works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_hour => { -ident => 'artist.when_began' } ] ]],
    sqlite => {
      stmt   => "SELECT STRFTIME('%H', artist.when_began) FROM artist",
      bind   => [],
    },
    msg    => '-dt_hour works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_minute => { -ident => 'artist.when_began' } ] ]],
    sqlite => {
      stmt   => "SELECT STRFTIME('%M', artist.when_began) FROM artist",
      bind   => [],
    },
    msg    => '-dt_minute works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_second => { -ident => 'artist.when_began' } ] ]],
    sqlite => {
      stmt   => "SELECT STRFTIME('%s', artist.when_began) FROM artist",
      bind   => [],
    },
    msg    => '-dt_second works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_diff => [second => { -ident => 'artist.when_ended' }, \'artist.when_began' ] ] ]],
    sqlite => {
      stmt   => "SELECT (STRFTIME('%s', artist.when_ended) - STRFTIME('%s', artist.when_began)) FROM artist",
      bind   => [],
    },
    msg    => '-dt_diff (second) works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_diff => [day => { -ident => 'artist.when_ended' }, \'artist.when_began' ] ] ]],
    sqlite => {
      stmt   => "SELECT (JULIANDAY(artist.when_ended) - JULIANDAY(artist.when_began)) FROM artist",
      bind   => [],
    },
    msg    => '-dt_diff (day) works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_add => [year => 3, { -ident => 'artist.when_ended' } ] ] ]],
    sqlite => {
      stmt   => "SELECT (datetime(artist.when_ended, ? || ' years')) FROM artist",
      bind   => [[ '', 3 ]],
    },
    msg    => '-dt_add (year) works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_add => [month => 3, { -ident => 'artist.when_ended' } ] ] ]],
    sqlite => {
      stmt   => "SELECT (datetime(artist.when_ended, ? || ' months')) FROM artist",
      bind   => [[ '', 3 ]],
    },
    msg    => '-dt_add (month) works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_add => [day => 3, { -ident => 'artist.when_ended' } ] ] ]],
    sqlite => {
      stmt   => "SELECT (datetime(artist.when_ended, ? || ' days')) FROM artist",
      bind   => [[ '', 3 ]],
    },
    msg    => '-dt_add (day) works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_add => [hour => 3, { -ident => 'artist.when_ended' } ] ] ]],
    sqlite => {
      stmt   => "SELECT (datetime(artist.when_ended, ? || ' hours')) FROM artist",
      bind   => [[ '', 3 ]],
    },
    msg    => '-dt_add (hour) works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_add => [minute => 3, { -ident => 'artist.when_ended' } ] ] ]],
    sqlite => {
      stmt   => "SELECT (datetime(artist.when_ended, ? || ' minutes')) FROM artist",
      bind   => [[ '', 3 ]],
    },
    msg    => '-dt_add (minute) works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_add => [second => 3, { -ident => 'artist.when_ended' } ] ] ]],
    sqlite => {
      stmt   => "SELECT (datetime(artist.when_ended, ? || ' seconds')) FROM artist",
      bind   => [[ '', 3 ]],
    },
    msg    => '-dt_add (second) works',
  },
  {
    func   => 'select',
    args   => ['artist', [ [ -dt_diff => [year => \'artist.when_started', { -ident => 'artist.when_ended' } ] ] ]],
    sqlite => {
      exception_like => qr/date diff not supported for part "year" with database "SQLite"/,
    },
  },
);

for my $t (@tests) {
  local $"=', ';

  DB_TEST:
  for my $db (keys %sql_maker) {
     my $maker = $sql_maker{$db};

     my $db_test = $t->{$db};
     next DB_TEST unless $db_test;

     my($stmt, @bind);

     my $cref = sub {
       my $op = $t->{func};
       ($stmt, @bind) = $maker->$op (@ { $t->{args} } );
     };

     if ($db_test->{exception_like}) {
       throws_ok(
         sub { $cref->() },
         $db_test->{exception_like},
         "throws the expected exception ($db_test->{exception_like})",
       );
     } else {
       if ($db_test->{warning_like}) {
         warning_like(
           sub { $cref->() },
           $db_test->{warning_like},
           "issues the expected warning ($db_test->{warning_like})"
         );
       }
       else {
         $cref->();
       }
       is_same_sql_bind(
         $stmt,
         \@bind,
         $db_test->{stmt},
         $db_test->{bind},
         ($t->{msg} ? $t->{msg} : ())
       );
     }
  }
}

done_testing;
