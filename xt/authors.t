use warnings;
use strict;

use Test::More;
use Config;
use File::Spec;

my @known_authors = do {
  # according to #p5p this is how one safely reads random unicode
  # this set of boilerplate is insane... wasn't perl unicode-king...?
  no warnings 'once';
  require Encode;
  require PerlIO::encoding;
  local $PerlIO::encoding::fallback = Encode::FB_CROAK();

  open (my $fh, '<:encoding(UTF-8)', 'AUTHORS') or die "Unable to open AUTHORS - can't happen: $!\n";
  map { chomp; ( ( ! $_ or $_ =~ /^\s*\#/ ) ? () : $_ ) } <$fh>;

} or die "Known AUTHORS file seems empty... can't happen...";

is_deeply (
  [ grep { /^\s/ or /\s\s/ } @known_authors ],
  [],
  "No entries with leading or doubled space",
);

is_deeply (
  [ grep { / \:[^\s\/] /x or /^ [^:]*? \s+ \: /x } @known_authors ],
  [],
  "No entries with malformed nicks",
);

is_deeply (
  \@known_authors,
  [ sort { lc $a cmp lc $b } @known_authors ],
  'Author list is case-insensitively sorted'
);

my $email_re = qr/( \< [^\<\>]+ \> ) $/x;

my (%known_authors, $count);
for (@known_authors) {
  my ($name_email) = m/ ^ (?: [^\:]+ \: \s )? (.+) /x;
  my ($email) = $name_email =~ $email_re;

  if (
    $known_authors{$name_email}++
      or
    ( $email and $known_authors{$email}++ )
  ) {
    fail "Duplicate found: $name_email";
  }
  else {
    $count++;
  }
}

# do not announce anything under travis - we are watching for STDERR silence
diag "\n\n$count contributors made this library what it is today\n\n"
  unless ($ENV{TRAVIS}||'') eq 'true';

# augh taint mode
if (length $ENV{PATH}) {
  ( $ENV{PATH} ) = join ( $Config{path_sep},
    map { length($_) ? File::Spec->rel2abs($_) : () }
      split /\Q$Config{path_sep}/, $ENV{PATH}
  ) =~ /\A(.+)\z/;
}

# this may fail - not every system has git
if (my @git_authors = map
  { my ($gitname) = m/^ \s* \d+ \s* (.+?) \s* $/mx; utf8::decode($gitname); $gitname }
  qx( git shortlog -e -s )
) {
  for (@git_authors) {
    my ($eml) = $_ =~ $email_re;

    fail "Commit author '$_' (from git) not reflected in AUTHORS, perhaps a missing .mailmap entry?"
      unless $known_authors{$eml};
  }
}

done_testing;
