package # hide from PAUSE
    SQL::Translator::Parser::DBIx::Class;

# AUTHOR: Jess Robinson

# Some mistakes the fault of Matt S Trout

# Others the fault of Ash Berlin

use strict;
use warnings;
use vars qw($DEBUG @EXPORT_OK);
$DEBUG = 0 unless defined $DEBUG;

use Exporter;
use Data::Dumper;
use Digest::SHA1 qw( sha1_hex );
use SQL::Translator::Utils qw(debug normalize_name);

use base qw(Exporter);

@EXPORT_OK = qw(parse);

# -------------------------------------------------------------------
# parse($tr, $data)
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

    $schema->name( ref($dbicschema) . " v" . ($dbicschema->VERSION || '1.x'))
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
                            name             => _create_unique_symbol($uniq),
                            fields           => $unique_constraints{$uniq}
                );
            }
        }

        my @rels = $source->relationships();

        my %created_FK_rels;

        foreach my $rel (sort @rels)
        {
            my $rel_info = $source->relationship_info($rel);

            # Ignore any rel cond that isn't a straight hash
            next unless ref $rel_info->{cond} eq 'HASH';

            my $othertable = $source->related_source($rel);
            my $rel_table = $othertable->name;

            # Force the order of @cond to match the order of ->add_columns
            my $idx;
            my %other_columns_idx = map {'foreign.'.$_ => ++$idx } $othertable->columns;            
            my @cond = sort { $other_columns_idx{$a} cmp $other_columns_idx{$b} } keys(%{$rel_info->{cond}}); 
      
            # Get the key information, mapping off the foreign/self markers
            my @refkeys = map {/^\w+\.(\w+)$/} @cond;
            my @keys = map {$rel_info->{cond}->{$_} =~ /^\w+\.(\w+)$/} @cond;

            if($rel_table)
            {
                my $reverse_rels = $source->reverse_relationship_info($rel);
                my ($otherrelname, $otherrelationship) = each %{$reverse_rels};

                my $on_delete = '';
                my $on_update = '';

                if (defined $otherrelationship) {
                    $on_delete = $otherrelationship->{'attrs'}->{cascade_delete} ? 'CASCADE' : '';
                    $on_update = $otherrelationship->{'attrs'}->{cascade_copy} ? 'CASCADE' : '';
                }

                my $is_deferrable = $rel_info->{attrs}{is_deferrable};

                # Make sure we dont create the same foreign key constraint twice
                my $key_test = join("\x00", @keys);

                #Decide if this is a foreign key based on whether the self
                #items are our primary columns.

                # If the sets are different, then we assume it's a foreign key from
                # us to another table.
                # OR: If is_foreign_key_constraint attr is explicity set (or set to false) on the relation
                next if ( exists $created_FK_rels{$rel_table}->{$key_test} );
                if ( exists $rel_info->{attrs}{is_foreign_key_constraint}) {
                  # not is this attr set to 0 but definitely if set to 1
                  next unless ($rel_info->{attrs}{is_foreign_key_constraint});
                } else {
                  # not if might have
                  # next if ($rel_info->{attrs}{accessor} eq 'single' && exists $rel_info->{attrs}{join_type} && uc($rel_info->{attrs}{join_type}) eq 'LEFT');
                  # not sure about this one
                  next if $source->compare_relationship_keys(\@keys, \@primary);
                }

                $created_FK_rels{$rel_table}->{$key_test} = 1;
                if (scalar(@keys)) {
                  $table->add_constraint(
                                    type             => 'foreign_key',
                                    name             => _create_unique_symbol($table->name
                                                                            . '_fk_'
                                                                            . join('_', @keys)),
                                    fields           => \@keys,
                                    reference_fields => \@refkeys,
                                    reference_table  => $rel_table,
                                    on_delete        => $on_delete,
                                    on_update        => $on_update,
                                    (defined $is_deferrable ? ( deferrable => $is_deferrable ) : ()),
                  );
                    
                  my $index = $table->add_index(
                                    name   => _create_unique_symbol(join('_', @keys)),
                                    fields => \@keys,
                                    type   => 'NORMAL',
                  );
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

# TODO - is there a reasonable way to pass configuration?
# Default of 64 comes from mysql's limit.
our $MAX_SYMBOL_LENGTH    ||= 64;
our $COLLISION_TAG_LENGTH ||= 8;

# -------------------------------------------------------------------
# $resolved_name = _create_unique_symbol($desired_name)
#
# If desired_name is really long, it will be truncated in a way that
# has a high probability of leaving it unique.
# -------------------------------------------------------------------
sub _create_unique_symbol {
    my $desired_name = shift;
    return $desired_name if length $desired_name <= $MAX_SYMBOL_LENGTH;

    my $truncated_name = substr $desired_name, 0, $MAX_SYMBOL_LENGTH - $COLLISION_TAG_LENGTH - 1;

    # Hex isn't the most space-efficient, but it skirts around allowed
    # charset issues
    my $digest = sha1_hex($desired_name);
    my $collision_tag = substr $digest, 0, $COLLISION_TAG_LENGTH;

    return $truncated_name
         . '_'
         . $collision_tag;
}

1;
