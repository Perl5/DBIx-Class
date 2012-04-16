# Makefile syntax allows adding extra dep-specs for already-existing targets,
# and simply appends them on *LAST*-come *FIRST*-serve basis.
# This allows us to inject extra depenencies for standard EUMM targets

postamble <<"EOP";

.PHONY: dbic_distdir_dbicadmin_pod_inject

distdir : dbic_distdir_dbicadmin_pod_inject

# The pod self-injection code is in fact a hidden option in
# dbicadmin itself, we execute the one in the distdir
dbic_distdir_dbicadmin_pod_inject :
\t\$(ABSPERL) -I\$(DISTVNAME)/lib \$(DISTVNAME)/script/dbicadmin --selfinject-pod

EOP

# keep the Makefile.PL eval happy
1;
