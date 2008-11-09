package SQL::Translator::Parser::DBIx::Class;

# AUTHOR: Jess Robinson

# Some mistakes the fault of Matt S Trout

# Others the fault of Ash Berlin

use strict;
use warnings;
use vars qw($DEBUG @EXPORT_OK);
$DEBUG = 0 unless defined $DEBUG;

use Exporter;
use Data::Dumper;
use SQL::Translator::Utils qw(debug normalize_name);

use base qw(Exporter);

@EXPORT_OK = qw(parse);

# -------------------------------------------------------------------
# parse($tr, $data)
#
# setting parser_args => { add_fk_index => 0 } will prevent
# the auto-generation of an index for each FK.
#
# Note that $data, in the case of this parser, is not useful.
# We're working with DBIx::Class Schemas, not data streams.
# -------------------------------------------------------------------
sub parse {
    my ($tr, $data)   = @_;
    my $args          = $tr->parser_args;
    my $dbicschema    = $args->{'DBIx::Class::Schema'} ||  $args->{"DBIx::Schema"} ||$data;
    $dbicschema     ||= $args->{'package'};
    my $limit_sources = $args->{'sources'};
    
    die 'No DBIx::Class::Schema' unless ($dbicschema);
    if (!ref $dbicschema) {
      eval "use $dbicschema;";
      die "Can't load $dbicschema ($@)" if($@);
    }

    my $schema      = $tr->schema;
    my $table_no    = 0;

    $schema->name( ref($dbicschema) . " v" . ($dbicschema->schema_version || '1.x'))
      unless ($schema->name);

    my %seen_tables;

    my @monikers = sort $dbicschema->sources;
    if ($limit_sources) {
        my $ref = ref $limit_sources || '';
        die "'sources' parameter must be an array or hash ref" unless $ref eq 'ARRAY' || ref eq 'HASH';

        # limit monikers to those specified in 
        my $sources;
        if ($ref eq 'ARRAY') {
            $sources->{$_} = 1 for (@$limit_sources);
        } else {
            $sources = $limit_sources;
        }
        @monikers = grep { $sources->{$_} } @monikers;
    }


    foreach my $moniker (sort @monikers)
    {
        my $source = $dbicschema->source($moniker);
        
        # Skip custom query sources
        next if ref($source->name);

        # Its possible to have multiple DBIC source using same table
        next if $seen_tables{$source->name}++;

        my $table = $schema->add_table(
                                       name => $source->name,
                                       type => 'TABLE',
                                       ) || die $schema->error;
        my $colcount = 0;
        foreach my $col ($source->columns)
        {
            # assuming column_info in dbic is the same as DBI (?)
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

        my @primary = $source->primary_columns;
        my %unique_constraints = $source->unique_constraints;
        foreach my $uniq (sort keys %unique_constraints) {
            if (!$source->compare_relationship_keys($unique_constraints{$uniq}, \@primary)) {
                $table->add_constraint(
                            type             => 'unique',
                            name             => $uniq,
                            fields           => $unique_constraints{$uniq}
                );
            }
        }

        my @rels = $source->relationships();

        my %created_FK_rels;
        
        # global add_fk_index set in parser_args
        my $add_fk_index = (exists $args->{add_fk_index} && ($args->{add_fk_index} == 0)) ? 0 : 1;

        foreach my $rel (sort @rels)
        {
            my $rel_info = $source->relationship_info($rel);

            # Ignore any rel cond that isn't a straight hash
            next unless ref $rel_info->{cond} eq 'HASH';

            my $othertable = $source->related_source($rel);
            my $rel_table = $othertable->name;

            my $reverse_rels = $source->reverse_relationship_info($rel);
            my ($otherrelname, $otherrelationship) = each %{$reverse_rels};

            # Force the order of @cond to match the order of ->add_columns
            my $idx;
            my %other_columns_idx = map {'foreign.'.$_ => ++$idx } $othertable->columns;            
            my @cond = sort { $other_columns_idx{$a} cmp $other_columns_idx{$b} } keys(%{$rel_info->{cond}}); 
      
            # Get the key information, mapping off the foreign/self markers
            my @refkeys = map {/^\w+\.(\w+)$/} @cond;
            my @keys = map {$rel_info->{cond}->{$_} =~ /^\w+\.(\w+)$/} @cond;

            # determine if this relationship is a self.fk => foreign.pk (i.e. belongs_to)
            my $fk_constraint;

            #first it can be specified explicitly
            if ( exists $rel_info->{attrs}{is_foreign_key_constraint} ) {
                $fk_constraint = $rel_info->{attrs}{is_foreign_key_constraint};
            }
            # it can not be multi
            elsif ( $rel_info->{attrs}{accessor}
                    && $rel_info->{attrs}{accessor} eq 'multi' ) {
                $fk_constraint = 0;
            }
            # if indeed single, check if all self.columns are our primary keys.
            # this is supposed to indicate a has_one/might_have...
            # where's the introspection!!?? :)
            else {
                $fk_constraint = not $source->compare_relationship_keys(\@keys, \@primary);
            }

            my $cascade;
            for my $c (qw/delete update/) {
                if (exists $rel_info->{attrs}{"on_$c"}) {
                    if ($fk_constraint) {
                        $cascade->{$c} = $rel_info->{attrs}{"on_$c"};
                    }
                    else {
                        warn "SQLT attribute 'on_$c' was supplied for relationship '$moniker/$rel', which does not appear to be a foreign constraint. "
                            . "If you are sure that SQLT must generate a constraint for this relationship, add 'is_foreign_key_constraint => 1' to the attributes.\n";
                    }
                }
                elsif (defined $otherrelationship and $otherrelationship->{attrs}{$c eq 'update' ? 'cascade_copy' : 'cascade_delete'}) {
                    $cascade->{$c} = 'CASCADE';
                }
            }

            if($rel_table)
            {
                # Constraints are added only if applicable
                next unless $fk_constraint;

                # Make sure we dont create the same foreign key constraint twice
                my $key_test = join("\x00", @keys);
                next if $created_FK_rels{$rel_table}->{$key_test};

                my $is_deferrable = $rel_info->{attrs}{is_deferrable};
                
                # global parser_args add_fk_index param can be overridden on the rel def
                my $add_fk_index_rel = (exists $rel_info->{attrs}{add_fk_index}) ? $rel_info->{attrs}{add_fk_index} : $add_fk_index;


                $created_FK_rels{$rel_table}->{$key_test} = 1;
                if (scalar(@keys)) {
                  $table->add_constraint(
                                    type             => 'foreign_key',
                                    name             => join('_', $table->name, 'fk', @keys),
                                    fields           => \@keys,
                                    reference_fields => \@refkeys,
                                    reference_table  => $rel_table,
                                    on_delete        => uc ($cascade->{delete} || ''),
                                    on_update        => uc ($cascade->{update} || ''),
                                    (defined $is_deferrable ? ( deferrable => $is_deferrable ) : ()),
                  );
                    
                  if ($add_fk_index_rel) {
                      my $index = $table->add_index(
                                                    name   => join('_', $table->name, 'idx', @keys),
                                                    fields => \@keys,
                                                    type   => 'NORMAL',
                                                    );
                  }
              }
            }
        }
		
        if ($source->result_class->can('sqlt_deploy_hook')) {
          $source->result_class->sqlt_deploy_hook($table);
        }
    }

    if ($dbicschema->can('sqlt_deploy_hook')) {
      $dbicschema->sqlt_deploy_hook($schema);
    }

    return 1;
}

1;

=head1 NAME

SQL::Translator::Parser::DBIx::Class - Create a SQL::Translator schema
from a DBIx::Class::Schema instance

=head1 SYNOPSIS

 use MyApp::Schema;
 use SQL::Translator;
 
 my $schema = MyApp::Schema->connect;
 my $trans  = SQL::Translator->new (
      parser      => 'SQL::Translator::Parser::DBIx::Class',
      parser_args => { package => $schema },
      producer    => 'SQLite',
     ) or die SQL::Translator->error;
 my $out = $trans->translate() or die $trans->error;

=head1 DESCRIPTION

C<SQL::Translator::Parser::DBIx::Class> reads a DBIx::Class schema,
interrogates the columns, and stuffs it all in an $sqlt_schema object.

=head1 SEE ALSO

SQL::Translator.

=head1 AUTHORS

Jess Robinson

Matt S Trout

Ash Berlin
