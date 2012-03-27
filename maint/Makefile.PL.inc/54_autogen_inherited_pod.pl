# generate the inherit pods as both a clone-dir step, and a makefile distdir step

print "Regenerating project documentation to include inherited methods\n";
# if the author doesn't have them, don't fail the initial "perl Makefile.pl" step
do "maint/gen_pod_inherit" or print "\n!!! FAILED: $@\n";

postamble <<"EOP";

.PHONY: dbic_clonedir_gen_inherit_pods

create_distdir : dbic_clonedir_gen_inherit_pods

dbic_clonedir_gen_inherit_pods :
\t\$(ABSPERL) maint/gen_pod_inherit

EOP

# keep the Makefile.PL eval happy
1;
