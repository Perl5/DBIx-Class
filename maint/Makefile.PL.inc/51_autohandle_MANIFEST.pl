# make sure manifest is deleted and generated anew on distdir
# preparation, and is deleted on realclean

postamble <<"EOM";

fresh_manifest : remove_manifest manifest

remove_manifest :
\t\$(RM) MANIFEST

realclean :: remove_manifest

EOM

# keep the Makefile.PL eval happy
1;
