# without having the pod in the file itself, perldoc may very
# well show a *different* document, because perl and perldoc
# search @INC differently (crazy right?)
#
# make sure we delete and re-create the file - just an append
# will not do what one expects, because on unixy systems the
# target is symlinked to the original
postamble <<"EOP";

create_distdir : dbic_distdir_dbicadmin_pod_inject

dbic_distdir_dbicadmin_pod_inject :
\t\$(RM_F) \$(DISTVNAME)/script/dbicadmin
\t@{[ $mm_proto->oneliner('cat', ['-MExtUtils::Command']) ]} script/dbicadmin maint/.Generated_Pod/dbicadmin.pod > \$(DISTVNAME)/script/dbicadmin

# FIXME also on win32 EU::Command::cat() adds crlf even if the
# source files do not contain any :(
@{[ $crlf_fixup->('$(DISTVNAME)/script/dbicadmin') ]}
EOP

# keep the Makefile.PL eval happy
1;
