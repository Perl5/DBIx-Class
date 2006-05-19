use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::HelperRels;

eval "use SQL::Translator";
plan skip_all => 'SQL::Translator required' if $@;

my $schema = DBICTest::Schema;

plan tests => 29;

my $translator           =  SQL::Translator->new( 
    parser_args          => {
        'DBIx::Schema'   => $schema,
    },
    producer_args   => {
    },
);

$translator->parser('SQL::Translator::Parser::DBIx::Class');
$translator->producer('SQLite');

my $output = $translator->translate();

my @constraints = 
 (
  {'display' => 'twokeys->cd',
   'selftable' => 'twokeys', 'foreigntable' => 'cd', 
   'selfcols'  => ['cd'], 'foreigncols' => ['cdid'], 
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'twokeys->artist',
   'selftable' => 'twokeys', 'foreigntable' => 'artist', 
   'selfcols'  => ['artist'], 'foreigncols' => ['artistid'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'cd_to_producer->cd',
   'selftable' => 'cd_to_producer', 'foreigntable' => 'cd', 
   'selfcols'  => ['cd'], 'foreigncols' => ['cdid'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'cd_to_producer->producer',
   'selftable' => 'cd_to_producer', 'foreigntable' => 'producer', 
   'selfcols'  => ['producer'], 'foreigncols' => ['producerid'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'self_ref_alias -> self_ref for self_ref',
   'selftable' => 'self_ref_alias', 'foreigntable' => 'self_ref', 
   'selfcols'  => ['self_ref'], 'foreigncols' => ['id'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'self_ref_alias -> self_ref for alias',
   'selftable' => 'self_ref_alias', 'foreigntable' => 'self_ref', 
   'selfcols'  => ['alias'], 'foreigncols' => ['id'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'cd -> artist',
   'selftable' => 'cd', 'foreigntable' => 'artist', 
   'selfcols'  => ['artist'], 'foreigncols' => ['artistid'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'artist_undirected_map -> artist for id1',
   'selftable' => 'artist_undirected_map', 'foreigntable' => 'artist', 
   'selfcols'  => ['id1'], 'foreigncols' => ['artistid'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'artist_undirected_map -> artist for id2',
   'selftable' => 'artist_undirected_map', 'foreigntable' => 'artist', 
   'selfcols'  => ['id2'], 'foreigncols' => ['artistid'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'track->cd',
   'selftable' => 'track', 'foreigntable' => 'cd', 
   'selfcols'  => ['cd'], 'foreigncols' => ['cdid'],
   'needed' => 2, on_delete => '', on_update => ''},
  {'display' => 'treelike -> treelike for parent',
   'selftable' => 'treelike', 'foreigntable' => 'treelike', 
   'selfcols'  => ['parent'], 'foreigncols' => ['id'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'twokeytreelike -> twokeytreelike for parent1,parent2',
   'selftable' => 'twokeytreelike', 'foreigntable' => 'twokeytreelike', 
   'selfcols'  => ['parent1', 'parent2'], 'foreigncols' => ['id1','id2'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'tags -> cd',
   'selftable' => 'tags', 'foreigntable' => 'cd', 
   'selfcols'  => ['cd'], 'foreigncols' => ['cdid'],
   'needed' => 1, on_delete => '', on_update => ''},
  {'display' => 'bookmark -> link',
   'selftable' => 'bookmark', 'foreigntable' => 'link', 
   'selfcols'  => ['link'], 'foreigncols' => ['id'],
   'needed' => 1, on_delete => '', on_update => ''},
 );

my $tschema = $translator->schema();
for my $table ($tschema->get_tables) {
    my $table_name = $table->name;
    for my $c ( $table->get_constraints ) {
        next unless $c->type eq 'FOREIGN KEY';

        ok(check($table_name, scalar $c->fields, 
              $c->reference_table, scalar $c->reference_fields, 
              $c->on_delete, $c->on_update), "Constraint on $table_name matches an expected constraint");
    }
}

my $i;
for ($i = 0; $i <= $#constraints; ++$i) {
 ok(!$constraints[$i]->{'needed'}, "Constraint $constraints[$i]->{display}");
}

sub check {
 my ($selftable, $selfcol, $foreigntable, $foreigncol, $ondel, $onupd) = @_;

 $ondel = '' if (!defined($ondel));
 $onupd = '' if (!defined($onupd));

 my $i;
 for ($i = 0; $i <= $#constraints; ++$i) {
     if ($selftable eq $constraints[$i]->{'selftable'} &&
         $foreigntable eq $constraints[$i]->{'foreigntable'} &&
         ($ondel eq $constraints[$i]->{on_delete}) &&
         ($onupd eq $constraints[$i]->{on_update})) {
         # check columns

         my $found = 0;
         for (my $j = 0; $j <= $#$selfcol; ++$j) {
             $found = 0;
             for (my $k = 0; $k <= $#{$constraints[$i]->{'selfcols'}}; ++$k) {
                 if ($selfcol->[$j] eq $constraints[$i]->{'selfcols'}->[$k] &&
                     $foreigncol->[$j] eq $constraints[$i]->{'foreigncols'}->[$k]) {
                     $found = 1;
                     last;
                 }
             }
             last unless $found;
         }

         if ($found) {
             for (my $j = 0; $j <= $#{$constraints[$i]->{'selfcols'}}; ++$j) {
                 $found = 0;
                 for (my $k = 0; $k <= $#$selfcol; ++$k) {
                     if ($selfcol->[$k] eq $constraints[$i]->{'selfcols'}->[$j] &&
                         $foreigncol->[$k] eq $constraints[$i]->{'foreigncols'}->[$j]) {
                         $found = 1;
                         last;
                     }
                 }
                 last unless $found;
             }
         }

         if ($found) {
             --$constraints[$i]->{needed};
             return 1;
         }
     }
 }
 return 0;
}
