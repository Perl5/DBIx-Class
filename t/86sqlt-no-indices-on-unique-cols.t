use strict;
use warnings;
use Data::Dumper;
use SQL::Translator;    # Why isn't that neccessary in t/86sqlt.t?

use Test::More;
use lib qw(t/lib);
use DBICTest;

BEGIN {
    require DBIx::Class;
    plan skip_all => 'Test needs '
        . DBIx::Class::Optional::Dependencies->req_missing_for('deploy')
        unless DBIx::Class::Optional::Dependencies->req_ok_for('deploy');
} ## end BEGIN

note(
    q(Checking there are no additional indices on first columns of unique constraints)
);

note q(Change schema initialization to deploy automatically);
my $schema = DBICTest->init_schema(no_deploy => 1, no_populate => 1);
note q(Remove the custom deployment callback);
for my $t ($schema->sources) {
    $schema->source($t)->sqlt_deploy_callback(
        sub {
            my ($self, $table) = @_;
            note qq(Table resource $table was just deployed);
            $self->default_sqlt_deploy_hook($table);
        }
    );
} ## end for my $t ($schema->sources)
$schema->deploy;

my $translator = SQL::Translator->new(
    parser_args   => { dbic_schema => $schema },
    parser        => q(SQL::Translator::Parser::DBIx::Class),
    producer_args => {},
) or die SQL::Translator->error;
my $tschema = $translator->schema;

TABLE: for ($schema->sources()) {
    my $source     = $schema->source($_);
    my $table_name = $source->name;
    note(
        Data::Dumper->Dump(
            [$_, $table_name],
            [qw( schema_source source_name_before )]
        )
    );
    my $tablename_type = ref $table_name;
    if ($tablename_type) {
        if ($tablename_type eq 'SCALAR') {
            $tablename_type = $$table_name;
        }
        else {
            note qq($_ type is skipped for unexpected type: $tablename_type);
            next TABLE;
        }
    } ## end if ($tablename_type)
    note(
        Data::Dumper->Dump(
            [$_, $table_name],
            [qw( schema_source source_name_after )]
        )
    );

    my %ucs = $source->unique_constraints;
    my @uc_first_cols = map { $ucs{$_}->[0] } keys %ucs;

    note qq(Searching indices of table $table_name);
    my $_t = $tschema->get_table($table_name);  # why are tables not populated??
    unless ($_t) {
        note qq(Table not found: $table_name);
        next;
    }

    my @index_first_cols = $_t->get_indices;

    # table "cd" is my first demonstration
    note(
        explain(
            {
                $table_name => {
                    unique_constraints => [@uc_first_cols],
                    relations          => [@index_first_cols],
                }
            }
        )
    ) if $_ eq q(CD);
} ## end TABLE: for ($schema->sources)

fail(q(!!! REMOVE ME WHEN FINISHED !!!));

done_testing();
