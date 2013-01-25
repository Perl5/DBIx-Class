# When a long-standing branch is updated a README may still linger around
unlink 'README' if -f 'README';

# Makefile syntax allows adding extra dep-specs for already-existing targets,
# and simply appends them on *LAST*-come *FIRST*-serve basis.
# This allows us to inject extra depenencies for standard EUMM targets

require File::Spec;
my $dir = File::Spec->catdir(qw(maint .Generated_Pod));
my $fn = File::Spec->catfile($dir, 'README');

postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_gen_readme

dbic_clonedir_gen_readme :
\t@{[ $mm_proto->oneliner('mkpath', ['-MExtUtils::Command']) ]} $dir
\tpod2text lib/DBIx/Class.pm > $fn

EOP

# keep the Makefile.PL eval happy
1;
