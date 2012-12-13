# leftovers in old checkouts
unlink 'lib/DBIx/Class/Optional/Dependencies.pod'
  if -f 'lib/DBIx/Class/Optional/Dependencies.pod';

my $pod_dir = '.generated_pod';
my $ver = Meta->version;

# cleanup the generated pod dir (again - kill leftovers from old checkouts)
require File::Path;
require File::Glob;
File::Path::rmtree( [File::Glob::bsd_glob "$pod_dir/*"], { verbose => 0 } );

# generate the OptDeps pod both in the clone-dir and during the makefile distdir
{
  print "Regenerating Optional/Dependencies.pod\n";
  require DBIx::Class::Optional::Dependencies;
  DBIx::Class::Optional::Dependencies->_gen_pod ($ver, $pod_dir);

  postamble <<"EOP";

.PHONY: dbic_clonedir_gen_optdeps_pod

create_distdir : dbic_clonedir_gen_optdeps_pod

dbic_clonedir_gen_optdeps_pod :
\t\$(ABSPERL) -Ilib -MDBIx::Class::Optional::Dependencies -e "DBIx::Class::Optional::Dependencies->_gen_pod(qw($ver $pod_dir))"

EOP
}

# generate the inherit pods both in the clone-dir and during the makefile distdir
{
  print "Regenerating project documentation to include inherited methods\n";

  # if the author doesn't have them, don't fail the initial "perl Makefile.pl" step
  do "maint/gen_pod_inherit" or print "\n!!! FAILED: $@\n";

  postamble <<"EOP";

.PHONY: dbic_clonedir_gen_inherit_pods

create_distdir : dbic_clonedir_gen_inherit_pods

dbic_clonedir_gen_inherit_pods :
\t\$(ABSPERL) -Ilib maint/gen_pod_inherit

EOP
}

# keep the Makefile.PL eval happy
1;
