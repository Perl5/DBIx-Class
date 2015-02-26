use warnings;
use strict;

use Test::More 'no_plan';

my $authorcount = scalar do {
  open (my $fh, '<', 'AUTHORS') or die "Unable to open AUTHORS - can't happen: $!\n";
  map { chomp; ( ( ! $_ or $_ =~ /^\s*\#/ ) ? () : $_ ) } <$fh>;
} or die "Known AUTHORS file seems empty... can't happen...";

# do not announce anything under travis - we are watching for STDERR silence
diag "\n\n$authorcount contributors made this library what it is today\n\n"
  unless ($ENV{TRAVIS}||'') eq 'true';

ok 1;
