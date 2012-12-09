# leftovers in old checkouts
unlink 'lib/DBIx/Class/Optional/Dependencies.pod'
  if -f 'lib/DBIx/Class/Optional/Dependencies.pod';

my $pod_dir = '.generated_pod';

# generate the pod as both a clone-dir step, and a makefile distdir step
my $ver = Meta->version;

print "Regenerating Optional/Dependencies.pod\n";
require DBIx::Class::Optional::Dependencies;
DBIx::Class::Optional::Dependencies->_gen_pod ($ver, $pod_dir);

postamble <<"EOP";

.PHONY: dbic_clonedir_gen_optdeps_pod

create_distdir : dbic_clonedir_gen_optdeps_pod

dbic_clonedir_gen_optdeps_pod :
\t\$(ABSPERL) -Ilib -MDBIx::Class::Optional::Dependencies -e "DBIx::Class::Optional::Dependencies->_gen_pod(qw($ver $pod_dir))"

EOP

# keep the Makefile.PL eval happy
1;
