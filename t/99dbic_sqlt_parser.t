use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;
use Scalar::Util ();

use lib qw(t/lib);
use DBICTest;
use DBIx::Class::_Util 'sigwarn_silencer';

BEGIN {
  require DBIx::Class;
  plan skip_all =>
      'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('deploy')
    unless DBIx::Class::Optional::Dependencies->req_ok_for ('deploy')
}

# Test for SQLT-related leaks
{
  my $s = DBICTest::Schema->clone;

  my @schemas = (
    create_schema ({ schema => $s }),
    create_schema ({ args => { parser_args => { dbic_schema => $s } } }),
  );

  for my $parser_args_key (qw(
    DBIx::Class::Schema
    DBIx::Schema
    package
  )) {
    warnings_exist {
      push @schemas, create_schema({
        args => { parser_args => { $parser_args_key => $s } }
      });
    } qr/\Qparser_args => {\E.+?is deprecated.+\Q@{[__FILE__]}/,
    "deprecated crazy parser_arg '$parser_args_key' warned";
  }

  Scalar::Util::weaken ($s);

  ok (!$s, 'Schema not leaked');

  isa_ok ($_, 'SQL::Translator::Schema', "SQLT schema object $_ produced")
    for @schemas;
}

# make sure classname-style works
lives_ok { isa_ok (create_schema ({ schema => 'DBICTest::Schema' }), 'SQL::Translator::Schema', 'SQLT schema object produced') };

# make sure a connected instance passed via $args does not get the $dbh improperly serialized
SKIP: {

  # YAML is a build_requires dep of SQLT - it may or may not be here
  eval { require YAML } or skip "Test requires YAML.pm", 1;

  lives_ok {

    my $s = DBICTest->init_schema(no_populate => 1);
    ok ($s->storage->connected, '$schema instance connected');

    # roundtrip through YAML
    my $yaml_rt_schema = SQL::Translator->new(
      parser => 'SQL::Translator::Parser::YAML'
    )->translate(
      data => SQL::Translator->new(
        parser_args => { dbic_schema => $s },
        parser => 'SQL::Translator::Parser::DBIx::Class',
        producer => 'SQL::Translator::Producer::YAML',
      )->translate
    );

    isa_ok ( $yaml_rt_schema, 'SQL::Translator::Schema', 'SQLT schema object produced after YAML roundtrip');

    ok ($s->storage->connected, '$schema instance still connected');
  }

  eval <<'EOE' or die $@;
  END {
    # we are in END - everything remains global
    #
    $^W = 1;  # important, otherwise DBI won't trip the next fail()
    $SIG{__WARN__} = sub {
      fail "Unexpected global destruction warning"
        if $_[0] =~ /is not a DBI/;
      warn @_;
    };
  }
EOE

}

my $schema = DBICTest->init_schema( no_deploy => 1 );

# Dummy was yanked out by the sqlt hook test
# CustomSql tests the horrific/deprecated ->name(\$sql) hack
# YearXXXXCDs are views
#
my @sources = grep
  { $_ !~ /^ (?: Dummy | CustomSql | Year\d{4}CDs ) $/x }
  $schema->sources
;

my $idx_exceptions = {
    'Artwork'       => -1,
    'ForceForeign'  => -1,
    'LinerNotes'    => -1,
    'TwoKeys'       => -1, # TwoKeys has the index turned off on the rel def
};

{
  my $sqlt_schema = create_schema({ schema => $schema, args => { parser_args => { } } });

  foreach my $source_name (@sources) {
    my $table = get_table($sqlt_schema, $schema, $source_name);

    my $fk_count = scalar(grep { $_->type eq 'FOREIGN KEY' } $table->get_constraints);
    $fk_count += $idx_exceptions->{$source_name} || 0;
    my @indices = $table->get_indices;

    my $index_count = scalar(@indices);
    is($index_count, $fk_count, "correct number of indices for $source_name with no args");

    for my $index (@indices) {
        my $source = $schema->source($source_name);
        my $pk_test = join("\x00", $source->primary_columns);
        my $idx_test = join("\x00", $index->fields);
        isnt ( $pk_test, $idx_test, "no additional index for the primary columns exists in $source_name");
    }
  }
}

{
  my $sqlt_schema = create_schema({ schema => $schema, args => { parser_args => { add_fk_index => 1 } } });

  foreach my $source_name (@sources) {
    my $table = get_table($sqlt_schema, $schema, $source_name);

    my $fk_count = scalar(grep { $_->type eq 'FOREIGN KEY' } $table->get_constraints);
    $fk_count += $idx_exceptions->{$source_name} || 0;
    my @indices = $table->get_indices;
    my $index_count = scalar(@indices);
    is($index_count, $fk_count, "correct number of indices for $source_name with add_fk_index => 1");
  }
}

{
  my $sqlt_schema = create_schema({ schema => $schema, args => { parser_args => { add_fk_index => 0 } } });

  foreach my $source (@sources) {
    my $table = get_table($sqlt_schema, $schema, $source);

    my @indices = $table->get_indices;
    my $index_count = scalar(@indices);
    is($index_count, 0, "correct number of indices for $source with add_fk_index => 0");
  }
}

{
    {
        package # hide from PAUSE
            DBICTest::Schema::NoViewDefinition;

        use base qw/DBICTest::BaseResult/;

        __PACKAGE__->table_class('DBIx::Class::ResultSource::View');
        __PACKAGE__->table('noviewdefinition');

        1;
    }

    my $schema_invalid_view = $schema->clone;
    $schema_invalid_view->register_class('NoViewDefinition', 'DBICTest::Schema::NoViewDefinition');

    throws_ok { create_schema({ schema => $schema_invalid_view }) }
        qr/view noviewdefinition is missing a view_definition/,
        'parser detects views with a view_definition';
}

lives_ok (sub {
  my $sqlt_schema = create_schema ({
    schema => $schema,
    args => {
      parser_args => {
        sources => ['CD']
      },
    },
  });

  is_deeply (
    [$sqlt_schema->get_tables ],
    ['cd'],
    'sources limitng with relationships works',
  );

});

{
  package DBICTest::PartialSchema;

  use base qw/DBIx::Class::Schema/;

  __PACKAGE__->load_classes(
    { 'DBICTest::Schema' => [qw/
      CD
      Track
      Tag
      Producer
      CD_to_Producer
    /]}
  );
}

{
  my $partial_schema = DBICTest::PartialSchema->connect(DBICTest->_database);

  lives_ok (sub {
    my $sqlt_schema = do {

      local $SIG{__WARN__} = sigwarn_silencer(
        qr/Ignoring relationship .+ related resultsource .+ is not registered with this schema/
      );

      create_schema({ schema => $partial_schema });
    };

    my @tables = $sqlt_schema->get_tables;

    is_deeply (
      [sort map { $_->name } @tables],
      [qw/cd cd_to_producer producer tags track/],
      'partial dbic schema parsing ok',
    );

    # the primary key is currently unnamed in sqlt - adding below
    my %constraints_for_table = (
      producer =>       [qw/prod_name                                                         /],
      tags =>           [qw/tagid_cd tagid_cd_tag tags_fk_cd tags_tagid_tag tags_tagid_tag_cd /],
      track =>          [qw/track_cd_position track_cd_title track_fk_cd                      /],
      cd =>             [qw/cd_artist_title cd_fk_single_track                                /],
      cd_to_producer => [qw/cd_to_producer_fk_cd cd_to_producer_fk_producer                   /],
    );

    for my $table (@tables) {
      my $tablename = $table->name;
      my @constraints = $table->get_constraints;
      is_deeply (
        [ sort map { $_->name } @constraints ],

        # the primary key (present on all loaded tables) is currently named '' in sqlt
        # subject to future changes
        [ '', @{$constraints_for_table{$tablename}} ],

        "constraints of table '$tablename' ok",
      );
    }
  }, 'partial schema tests successful');
}

{
  my $cd_rsrc = $schema->source('CD');
  $cd_rsrc->name(\'main.cd');

  my $sqlt_schema = create_schema(
    { schema => $schema },
    args => { ignore_constraint_names => 0, ignore_index_names => 0 }
  );

  foreach my $source_name (qw(CD)) {
    my $table = get_table($sqlt_schema, $schema, $source_name);
    ok(
      !(grep {$_->name =~ m/main\./} $table->get_indices),
      'indices have periods stripped out'
    );
    ok(
      !(grep {$_->name =~ m/main\./} $table->get_constraints),
      'constraints have periods stripped out'
    );
  }
}

done_testing;

sub create_schema {
  my $args = shift;

  my $additional_sqltargs = $args->{args} || {};

  my $sqltargs = {
    add_drop_table => 1,
    ignore_constraint_names => 1,
    ignore_index_names => 1,
    %{$additional_sqltargs}
  };

  my $sqlt = SQL::Translator->new( $sqltargs );

  $sqlt->parser('SQL::Translator::Parser::DBIx::Class');
  return $sqlt->translate(
    $args->{schema} ? ( data => $args->{schema} ) : ()
  ) || die $sqlt->error;
}

sub get_table {
    my ($sqlt_schema, $schema, $source) = @_;

    my $table_name = $schema->source($source)->from;
    $table_name    = $$table_name if ref $table_name;

    return $sqlt_schema->get_table($table_name);
}
