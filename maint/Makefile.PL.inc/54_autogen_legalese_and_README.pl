# When a long-standing branch is updated a README may still linger around
unlink 'README' if -f 'README';

# Makefile syntax allows adding extra dep-specs for already-existing targets,
# and simply appends them on *LAST*-come *FIRST*-serve basis.
# This allows us to inject extra depenencies for standard EUMM targets

require File::Spec;
my $dir = File::Spec->catdir(qw(maint .Generated_Pod));
my $r_fn = File::Spec->catfile($dir, 'README');

my $start_file = sub {
  my $fn = $mm_proto->quote_literal(shift);
  return join "\n",
    qq{\t\$(NOECHO) \$(RM_F) $fn},
    ( map { qq(\t\$(NOECHO) \$(ECHO) "$_" >> $fn) } (
      "DBIx::Class is Copyright (c) 2005-@{[ (gmtime)[5] + 1900  ]} by mst, castaway, ribasushi, and others.",
      "See AUTHORS and LICENSE included with this distribution. All rights reserved.",
      "",
    )),
  ;
};

postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_gen_readme

dbic_clonedir_gen_readme : dbic_distdir_gen_dbic_pod
@{[ $start_file->($r_fn) ]}
\tpod2text $dir/lib/DBIx/Class.pod >> $r_fn

create_distdir : dbic_distdir_regen_license

dbic_distdir_regen_license :
@{[ $start_file->( File::Spec->catfile( Meta->name . '-' . Meta->version, 'LICENSE') ) ]}
\t@{[ $mm_proto->oneliner('cat', ['-MExtUtils::Command']) ]} LICENSE >> \$(DISTVNAME)/LICENSE

EOP


# keep the Makefile.PL eval happy
1;
