use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::HelperRels;

eval "use SQL::Translator";
plan skip_all => 'SQL::Translator required' if $@;

my $schema = DBICTest::Schema;

plan tests => 31;

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

my @fk_constraints = 
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
 );

my @unique_constraints = (
  {'display' => 'cd artist and title unique',
   'table' => 'cd', 'cols' => ['artist', 'title'],
   'needed' => 1},
  {'display' => 'twokeytreelike name unique',
   'table' => 'twokeytreelike', 'cols'  => ['name'],
   'needed' => 1},
);

my $tschema = $translator->schema();
for my $table ($tschema->get_tables) {
    my $table_name = $table->name;
    for my $c ( $table->get_constraints ) {
        if ($c->type eq 'FOREIGN KEY') {
            ok(check_fk($table_name, scalar $c->fields, 
                  $c->reference_table, scalar $c->reference_fields, 
                  $c->on_delete, $c->on_update), "Foreign key constraint on $table_name matches an expected constraint");
        }
        elsif ($c->type eq 'UNIQUE') {
            ok(check_unique($table_name, scalar $c->fields),
                  "Unique constraint on $table_name matches an expected constraint");
        }
    }
}

# Make sure all the foreign keys are done.
my $i;
for ($i = 0; $i <= $#fk_constraints; ++$i) {
 ok(!$fk_constraints[$i]->{'needed'}, "Constraint $fk_constraints[$i]->{display}");
}
# Make sure all the uniques are done.
for ($i = 0; $i <= $#unique_constraints; ++$i) {
 ok(!$unique_constraints[$i]->{'needed'}, "Constraint $unique_constraints[$i]->{display}");
}

sub check_fk {
 my ($selftable, $selfcol, $foreigntable, $foreigncol, $ondel, $onupd) = @_;

 $ondel = '' if (!defined($ondel));
 $onupd = '' if (!defined($onupd));

 my $i;
 for ($i = 0; $i <= $#fk_constraints; ++$i) {
     if ($selftable eq $fk_constraints[$i]->{'selftable'} &&
         $foreigntable eq $fk_constraints[$i]->{'foreigntable'} &&
         ($ondel eq $fk_constraints[$i]->{on_delete}) &&
         ($onupd eq $fk_constraints[$i]->{on_update})) {
         # check columns

         my $found = 0;
         for (my $j = 0; $j <= $#$selfcol; ++$j) {
             $found = 0;
             for (my $k = 0; $k <= $#{$fk_constraints[$i]->{'selfcols'}}; ++$k) {
                 if ($selfcol->[$j] eq $fk_constraints[$i]->{'selfcols'}->[$k] &&
                     $foreigncol->[$j] eq $fk_constraints[$i]->{'foreigncols'}->[$k]) {
                     $found = 1;
                     last;
                 }
             }
             last unless $found;
         }

         if ($found) {
             for (my $j = 0; $j <= $#{$fk_constraints[$i]->{'selfcols'}}; ++$j) {
                 $found = 0;
                 for (my $k = 0; $k <= $#$selfcol; ++$k) {
                     if ($selfcol->[$k] eq $fk_constraints[$i]->{'selfcols'}->[$j] &&
                         $foreigncol->[$k] eq $fk_constraints[$i]->{'foreigncols'}->[$j]) {
                         $found = 1;
                         last;
                     }
                 }
                 last unless $found;
             }
         }

         if ($found) {
             --$fk_constraints[$i]->{needed};
             return 1;
         }
     }
 }
 return 0;
}

sub check_unique {
 my ($selftable, $selfcol) = @_;

 $ondel = '' if (!defined($ondel));
 $onupd = '' if (!defined($onupd));

 my $i;
 for ($i = 0; $i <= $#unique_constraints; ++$i) {
     if ($selftable eq $unique_constraints[$i]->{'table'}) {

         my $found = 0;
         for (my $j = 0; $j <= $#$selfcol; ++$j) {
             $found = 0;
             for (my $k = 0; $k <= $#{$unique_constraints[$i]->{'cols'}}; ++$k) {
                 if ($selfcol->[$j] eq $unique_constraints[$i]->{'cols'}->[$k]) {
                     $found = 1;
                     last;
                 }
             }
             last unless $found;
         }

         if ($found) {
             for (my $j = 0; $j <= $#{$unique_constraints[$i]->{'cols'}}; ++$j) {
                 $found = 0;
                 for (my $k = 0; $k <= $#$selfcol; ++$k) {
                     if ($selfcol->[$k] eq $unique_constraints[$i]->{'cols'}->[$j]) {
                         $found = 1;
                         last;
                     }
                 }
                 last unless $found;
             }
         }

         if ($found) {
             --$unique_constraints[$i]->{needed};
             return 1;
         }
     }
 }
 return 0;
}
