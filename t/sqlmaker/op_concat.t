use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use Storable qw(dclone);

use_ok('DBICTest');

my $schema = DBICTest->init_schema();
my $sql_maker = $schema->storage->sql_maker;
our $storage = $schema->storage->sql_maker_class;
$storage =~ s/^.+::(\w+)$/$1/;

# Yes, this is a little weird, but we can't exactly use
# the same function to test that function, can we?
sub concat_check {
  if    ($storage eq 'MSSQL')    { return join(' + ' , @_); }
  elsif ($storage eq 'ACCESS')   { return join(' & ' , @_); }
  elsif ($storage =~ /mysql|Pg/) { return 'CONCAT('   .join(', ', @_).')'; }   ### FIXME: Need check for Pg version here ###
  return join(' || ', @_);
}
sub concat_ws_check {
  if    ($storage =~ /mysql|Pg/) { return 'CONCAT_WS('.join(', ', @_).')'; }   ### FIXME: Need check for Pg version here ###

  my @new = @_;
  my $sep = shift @new;
  @new = map { ($_, $sep) } @new;
  pop @new;  # remove trailing separator

  if    ($storage eq 'MSSQL')    { return join(' + ' , @new); }
  elsif ($storage eq 'ACCESS')   { return join(' & ' , @new); }
  return join(' || ', @new);
}

for my $ws ('concat', 'concat_ws') {
  my $sep = ($ws eq 'concat_ws') ? \'!!' : '';
  for my $q ('', '"') {

    my $ident_obj = [
      {
        obj => '25',
        sql => '?',
      },
      {
        obj => \'artist.literal',
        sql => "artist.literal",
      },
      {
        obj => { -ident => 'artist.pseudonym' },
        sql => "${q}artist${q}.${q}pseudonym${q}",
      },
    ];

    $sql_maker->quote_char($q);

    for my $i (0 .. @$ident_obj-1) {
      my ($iobj, $isql) = (map { $ident_obj->[$i]{$_} } (qw/obj sql/));

      my $concat_obj = [
        { # Single concat (should be basically nothing changed)
          obj => [ $iobj ],
          sql => [ $isql ],
        },
        { # "ABC" concat
          obj => [ $iobj, $iobj, $iobj ],
          sql => [ $isql, $isql, $isql ],
        },
        { # "A-B" concat
          obj => [ $iobj, \"$q-$q", $iobj ],
          sql => [ $isql, "$q-$q",  $isql ],
        },
        { # "A B" concat
          obj => [ $iobj, \"$q $q", $iobj ],
          sql => [ $isql, "$q $q",  $isql ],
        },
        { # Absolute madness...
          obj => [
            $iobj,
            { avg => [ $iobj, { -concat => [ $iobj, \"$q AND THEN $q", $iobj ] } ] },
            $iobj,
          ],
          sql => [ $isql, "AVG(".$isql.", ".concat_check($isql, "$q AND THEN $q", $isql).')', $isql ],
        },
      ];

      if ($sep) {
        unshift(@{$_->{obj}},  $sep) for (@$concat_obj);
        unshift(@{$_->{sql}}, $$sep) for (@$concat_obj);
      }

      for my $c (0 .. @$concat_obj-1) {
        my ($cobj, $csql) = (map { $concat_obj->[$c]{$_} } (qw/obj sql/));
        my $unchanged = dclone $cobj;
        my $key = "$ws-".($q ? 'quote-' : 'noquote-')."$i-$c";

        # use approp concat_check func
        no strict 'refs';
        $csql = &{$ws.'_check'}(@$csql);

        # (only optional on single param WHERE clauses)
        my $pa = ($c ? '(' : '');
        my $pz = ($c ? ')' : '');
        # FIXME!!!
        # SET does not seem to support parenthesis in most dialects
        $pa = $pz = '';


        #local $TODO = "Problems with AVG function interpretation" if ($c == @$concat_obj-1);
        next if ($c == @$concat_obj-1);

        my $ws_obj = [ "-$ws" => $cobj ];
        my $binds_with_name = [ map { [ "${q}artist${q}.${q}name${q}", $iobj ] } ($csql =~ /\?/g) ];  # can't use x @ because they have the same ref
        my $binds_wo_name   = [ map { [                         undef, $iobj ] } ($csql =~ /\?/g) ];

        my $select_obj = [
          {
            descr  => 'SELECT WHERE name = CSQL',
            params => [ '*', { 'artist.name' => {@$ws_obj} } ],
            sql    => "SELECT *
                       FROM ${q}artist${q}
                       WHERE $pa ${q}artist${q}.${q}name${q} = $csql $pz",
            binds  => $binds_with_name,
          },
          {
            descr  => 'SELECT WHERE CSQL',
            params => [ '*', [ {@$ws_obj} ] ],
            sql    => "SELECT *
                       FROM ${q}artist${q}
                       WHERE $pa $csql $pz",
            binds  => $binds_wo_name,
          },
          {
            descr  => 'SELECT CSQL',
            params => [ [ $ws_obj ] ],
            sql    => "SELECT $csql FROM ${q}artist${q}",
            binds  => $binds_wo_name,
          },
          {
            descr  => 'SELECT WHERE name = CSQL',
            params => [ '*', { 'artist.name' => {@$ws_obj} } ],
            sql    => "SELECT *
                       FROM ${q}artist${q}
                       WHERE $pa ${q}artist${q}.${q}name${q} = $csql $pz",
            binds  => $binds_with_name,
          },
          {
            descr  => 'SELECT name, CSQL',
            params => [ [ 'artist.name', $ws_obj ] ],
            sql    => "SELECT ${q}artist${q}.${q}name${q}, $csql FROM ${q}artist${q}",
            binds  => $binds_wo_name,
          },
          {
            descr  => 'SELECT name, CSQL WHERE name = CSQL',
            params => [ [ 'artist.name', $ws_obj ], { 'artist.name' => {@$ws_obj} } ],
            sql    => "SELECT ${q}artist${q}.${q}name${q}, $csql
                       FROM ${q}artist${q}
                       WHERE $pa ${q}artist${q}.${q}name${q} = $csql $pz",
            binds  => [@$binds_wo_name, @$binds_with_name]
          },
        ];

        for my $s (0 .. @$select_obj-1) {
          my $sobj = $select_obj->[$s];

          is_same_sql_bind (
            \[ $sql_maker->select ('artist', @{$sobj->{params}}) ],
            $sobj->{sql},
            $sobj->{binds},
            "$key-$s --> ".$sobj->{descr},
          );
          is_deeply($cobj, $unchanged, "$key-$s --> ".$sobj->{descr}." --> CObj is unchanged");
        }

        is_same_sql_bind (
          \[ $sql_maker->update ('artist',
            { 'artist.name' => {@$ws_obj} },
            { 'artist.name' => { '!=' => {@$ws_obj} } },
          ) ],
          "UPDATE ${q}artist${q}
            SET $pa ${q}artist${q}.${q}name${q} = ".$csql." $pz
            WHERE $pa ${q}artist${q}.${q}name${q} != ".$csql." $pz
          ",
          [@$binds_wo_name, @{dclone $binds_wo_name}],  ### XXX: Should those really be undef (wo_name)? ###
          "$key --> UPDATE SET name = CSQL WHERE name != CSQL",
        );
        is_deeply($cobj, $unchanged, "$key --> UPDATE SET name = CSQL WHERE name != CSQL --> CObj is unchanged");
      }
    }
  }
}

done_testing;
