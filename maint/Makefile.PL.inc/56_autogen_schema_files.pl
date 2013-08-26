require File::Spec;
my $test_ddl_fn = File::Spec->catfile(qw( t lib sqlite.sql ));
my @test_ddl_cmd = qw( -I lib -I t/lib -- maint/gen_sqlite_schema_files --schema-class DBICTest::Schema );

# If the author doesn't have the prereqs, still generate a Makefile
# The EUMM build-stage generation will run unconditionally and
# errors will not be ignored unlike here
require DBIx::Class::Optional::Dependencies;
if ( DBIx::Class::Optional::Dependencies->req_ok_for ('deploy') ) {
  print "Regenerating $test_ddl_fn\n";
  system( $^X, @test_ddl_cmd, '--ddl-out' => $test_ddl_fn );

  # if we don't do it some git tools (e.g. gitk) get confused that the
  # ddl file is modified, when it clearly isn't
  system('git status --porcelain >' . File::Spec->devnull);
}

postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_regen_test_ddl

dbic_clonedir_regen_test_ddl :
\t\$(ABSPERLRUN) @test_ddl_cmd --ddl-out @{[ $mm_proto->quote_literal($test_ddl_fn) ]}
EOP

# keep the Makefile.PL eval happy
1;
