package # hide from PAUSE 
    SQL::Translator::Parser::DBIx::Class;

# AUTHOR: Jess Robinson

# Some mistakes the fault of Matt S Trout

use strict;
use warnings;
use vars qw($DEBUG $VERSION @EXPORT_OK);
$DEBUG = 0 unless defined $DEBUG;
$VERSION = sprintf "%d.%02d", q$Revision 1.0$ =~ /(\d+)\.(\d+)/;

use Exporter;
use Data::Dumper;
use SQL::Translator::Utils qw(debug normalize_name);

use base qw(Exporter);

@EXPORT_OK = qw(parse);

# -------------------------------------------------------------------
# parse($tr, $data)
#
# Note that $data, in the case of this parser, is unuseful.
# We're working with DBIx::Class Schemas, not data streams.
# -------------------------------------------------------------------
sub parse {
    my ($tr, $data) = @_;
    my $args        = $tr->parser_args;
    my $dbixschema  = $args->{'DBIx::Schema'} || $data;
    $dbixschema   ||= $args->{'package'};
    
    die 'No DBIx::Schema' unless ($dbixschema);
    if (!ref $dbixschema) {
      eval "use $dbixschema;";
      die "Can't load $dbixschema ($@)" if($@);
    }

    my $schema      = $tr->schema;
    my $table_no    = 0;

#    print Dumper($dbixschema->registered_classes);

    #foreach my $tableclass ($dbixschema->registered_classes)
    foreach my $moniker ($dbixschema->sources)
    {
        #eval "use $tableclass";
        #print("Can't load $tableclass"), next if($@);
        my $source = $dbixschema->source($moniker);

        my $table = $schema->add_table(
                                       name => $source->name,
                                       type => 'TABLE',
                                       ) || die $schema->error;
        my $colcount = 0;
        foreach my $col ($source->columns)
        {
            # assuming column_info in dbix is the same as DBI (?)
            # data_type is a number, column_type is text?
            my %colinfo = (
              name => $col,
              size => 0,
              is_auto_increment => 0,
              is_foreign_key => 0,
              is_nullable => 0,
              %{$source->column_info($col)}
            );
            if ($colinfo{is_nullable}) {
              $colinfo{default} = '' unless exists $colinfo{default};
            }
            my $f = $table->add_field(%colinfo) || die $table->error;
        }
        $table->primary_key($source->primary_columns);

        my @rels = $source->relationships();
        foreach my $rel (@rels)
        {
            my $rel_info = $source->relationship_info($rel);
            next if(!exists $rel_info->{attrs}{accessor} ||
                    $rel_info->{attrs}{accessor} eq 'multi');
            # Going by the accessor type isn't such a good idea (yes, I know
            # I suggested it). I think the best way to tell if something's a
            # foreign key constraint is to assume if it doesn't include our
            # primaries then it is (dumb but it'll do). Ignore any rel cond
            # that isn't a straight hash, but get both sets of keys in full
            # so you don't barf on multi-primaries. Oh, and a dog-simple
            # deploy method to chuck the results of this exercise at a db
            # for testing is
            # $schema->storage->dbh->do($_) for split(";\n", $sql);
            #         -- mst (03:42 local time, please excuse any mistakes)
            my $rel_table = $source->related_source($rel)->name;
            my $cond = (keys (%{$rel_info->{cond}}))[0];
            my ($refkey) = $cond =~ /^\w+\.(\w+)$/;
            my ($key) = $rel_info->{cond}->{$cond} =~ /^\w+\.(\w+)$/;
            if($rel_table && $refkey)
            { 
                $table->add_constraint(
                            type             => 'foreign_key', 
                            name             => "fk_${key}",
                            fields           => $key,
                            reference_fields => $refkey,
                            reference_table  => $rel_table,
                );
            }
        }
    }

}    

1;
