# When a long-standing branch is updated a README may still inger around
unlink 'README' if -f 'README';

# Makefile syntax allows adding extra dep-specs for already-existing targets,
# and simply appends them on *LAST*-come *FIRST*-serve basis.
# This allows us to inject extra depenencies for standard EUMM targets

postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_gen_readme

clonedir_cleanup_generated_files : dbic_clonedir_cleanup_readme

dbic_clonedir_gen_readme :
\tpod2text lib/DBIx/Class.pm > README

dbic_clonedir_cleanup_readme :
\t\$(RM_F) README

realclean :: dbic_clonedir_cleanup_readme

EOP

# keep the Makefile.PL eval happy
1;
