die "Makefile.PL does not seem to have been executed from the root distdir\n"
  unless -d 'lib';

# $FindBin::Bin is the location of the inluding Makefile.PL, not this file
require FindBin;
unshift @INC, "$FindBin::Bin/lib";

# adjust ENV for $AUTHOR system() calls
require Config;
$ENV{PERL5LIB} = join ($Config::Config{path_sep}, @INC);

# keep the Makefile.PL eval happy
1;
