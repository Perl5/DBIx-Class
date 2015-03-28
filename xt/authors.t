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

my %known_authors;
for (@known_authors) {
  my ($name_email) = m/ ^ (?: [^\:]+ \: \s )? (.+) /x;
  my ($email) = $name_email =~ $email_re;

  fail "Duplicate found: $name_email" if (
    $known_authors{$name_email}++
      or
    ( $email and $known_authors{$email}++ )
  );
}

# augh taint mode
if (length $ENV{PATH}) {
  ( $ENV{PATH} ) = join ( $Config{path_sep},
    map { length($_) ? File::Spec->rel2abs($_) : () }
      split /\Q$Config{path_sep}/, $ENV{PATH}
  ) =~ /\A(.+)\z/;
}

# no git-check when smoking a PR
if (
  (
    ! $ENV{TRAVIS_PULL_REQUEST}
      or
    $ENV{TRAVIS_PULL_REQUEST} eq "false"
  )
    and
  -d '.git'
) {

  binmode (Test::More->builder->$_, ':utf8') for qw/output failure_output todo_output/;

  # this may fail - not every system has git
  for (
    map
      { my ($gitname) = m/^ \s* \d+ \s* (.+?) \s* $/mx; utf8::decode($gitname); $gitname }
      qx( git shortlog -e -s )
  ) {
    my ($eml) = $_ =~ $email_re;

    ok $known_authors{$eml},
      "Commit author '$_' (from .mailmap-aware `git shortlog -e -s`) reflected in ./AUTHORS";
  }
}

done_testing;
