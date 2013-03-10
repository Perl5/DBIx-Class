# make sure manifest is deleted and generated anew on distdir
# preparation, and is deleted on realclean

postamble <<"EOM";

fresh_manifest : remove_manifest manifest

remove_manifest :
\t\$(RM_F) MANIFEST

realclean :: remove_manifest

manifest : check_manifest_is_lone_target

check_manifest_is_lone_target :
\t\$(NOECHO) @{[
  $mm_proto->oneliner('q($(MAKECMDGOALS)) =~ /(\S*manifest\b)/ and q($(MAKECMDGOALS)) ne $1 and die qq(The DBIC build chain does not support mixing the $1 target with others\n)')
]}

EOM

# keep the Makefile.PL eval happy
1;
