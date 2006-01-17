package SQL::Translator::Parser::DBIx::Class;

# AUTHOR: Jess Robinson

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
    
    die 'No DBIx::Schema' unless ($dbixschema);
    if (!ref $dbixschema) {
      eval "use $dbixschema;";
      die "Can't load $dbixschema ($@)" if($@);
    }

    my $schema      = $tr->schema;
    my $table_no    = 0;

#    print Dumper($dbixschema->registered_classes);

    foreach my $tableclass ($dbixschema->registered_classes)
    {
        eval "use $tableclass";
        print("Can't load $tableclass"), next if($@);
        my $source = $tableclass->result_source_instance;

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
              default_value => '',
              size => 0,
              is_auto_increment => 0,
              is_foreign_key => 0,
              is_nullable => 0,
              %{$source->column_info($col)}
            );
            my $f = $table->add_field(%colinfo) || die $table->error;
        }
        $table->primary_key($source->primary_columns);


        my @rels = $source->relationships();
        foreach my $rel (@rels)
        {
            my $rel_info = $source->relationship_info($rel);
            print "Accessor: $rel_info->{attrs}{accessor}\n";
            next if(!exists $rel_info->{attrs}{accessor} ||
                    $rel_info->{attrs}{accessor} ne 'filter');
            my $rel_table = $source->related_source($rel)->name; # rel_info->{class}->table();
            my $cond = (keys (%{$rel_info->{cond}}))[0];
            my ($refkey) = $cond =~ /^\w+\.(\w+)$/;
            if($rel_table && $refkey)
            {
                $table->add_constraint(
                            type             => 'foreign_key', 
                            name             => "fk_${rel}_id",
                            fields           => $rel,
                            reference_fields => $refkey,
                            reference_table  => $rel_table,
                                       );
            }
        }
    }

}    

1;
