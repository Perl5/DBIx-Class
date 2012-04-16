# Makefile syntax allows adding extra dep-specs for already-existing targets,
# and simply appends them on *LAST*-come *FIRST*-serve basis.
# This allows us to inject extra depenencies for standard EUMM targets

postamble <<"EOP";

.PHONY: dbic_clonedir_cleanup_readme dbic_clonedir_gen_readme

distdir : dbic_clonedir_cleanup_readme

create_distdir : dbic_clonedir_gen_readme

dbic_clonedir_gen_readme :
\tpod2text lib/DBIx/Class.pm > README

dbic_clonedir_cleanup_readme :
\t\$(RM_F) README

EOP

# keep the Makefile.PL eval happy
1;
