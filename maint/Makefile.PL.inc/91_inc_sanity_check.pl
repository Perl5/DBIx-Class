my @files_to_check = qw(AutoInstall.pm Can.pm WriteAll.pm Win32.pm);

END {
  # shit already hit the fan
  return if $?;

  for my $f (@files_to_check) {
    if (! -f "inc/Module/Install/$f") {
      warn "Your inc/ does not contain a critical Module::Install component - \$_. Something went horrifically wrong... please ask the cabal for help\n";
      unlink 'Makefile';
      exit 1;
    }
  }
}

my $oneliner = <<"EOO";
-f qq(\$(DISTVNAME)/inc/Module/Install/\$_) or die "\\nYour \$(DISTVNAME)/inc/ does not contain a critical Module::Install component: \$_. Something went horrifically wrong... please ask the cabal for help\\n\\n" for (qw(@files_to_check))
EOO

postamble <<"EOP";
create_distdir : sanity_check_inc

sanity_check_inc :
\t\$(NOECHO) @{[ $mm_proto->oneliner($oneliner) ]}

EOP

# keep the Makefile.PL eval happy
1;
