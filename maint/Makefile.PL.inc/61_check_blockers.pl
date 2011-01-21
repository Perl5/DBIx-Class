# Makefile syntax allows adding extra dep-specs for already-existing targets,
# and simply appends them on *LAST*-come *FIRST*-serve basis.
# This allows us to inject extra depenencies for standard EUMM targets

preamble <<EOP;

.PHONY: dbicdist_check_blockers

create_distdir : dbicdist_check_blockers

dbicdist_check_blockers :
\t\$(ABSPERL) maint/dbic_todo --check-blockers

EOP

# keep the Makefile.PL eval happy
1;
