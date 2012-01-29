# Makefile syntax allows adding extra dep-specs for already-existing targets,
# and simply appends them on *LAST*-come *FIRST*-serve basis.
# This allows us to inject extra depenencies for standard EUMM targets

print "Removing MANIFEST, will regenerate on next `make dist(dir)`\n";
unlink 'MANIFEST';

# preamble. so that the manifest target is first, hence executes last
preamble <<"EOP";

create_distdir : manifest

EOP

# keep the Makefile.PL eval happy
1;
