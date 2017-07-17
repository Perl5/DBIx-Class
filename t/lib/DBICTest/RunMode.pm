package # hide from PAUSE
    DBICTest::RunMode;

use strict;
use warnings;

# Mimic $Module::Install::AUTHOR
sub is_author {
  return (
    ! -d 'inc/Module'
      or
    -e 'inc/.author'
  );
}

sub is_smoker {
  return (
    ( $ENV{AUTOMATED_TESTING} && ! $ENV{PERL5_CPANM_IS_RUNNING} && ! $ENV{RELEASE_TESTING} )
      or
    __PACKAGE__->is_ci
  );
}

sub is_ci {
  return (
    ($ENV{TRAVIS}||'') eq 'true'
      and
    ($ENV{TRAVIS_REPO_SLUG}||'') =~ m|\w+/dbix-class$|
  )
}

sub is_plain {
  return (
    ! $ENV{RELEASE_TESTING}
      and
    ! $ENV{DBICTEST_RUN_ALL_TESTS}
      and
    ! __PACKAGE__->is_smoker
      and
    ! __PACKAGE__->is_author
  )
}

1;
