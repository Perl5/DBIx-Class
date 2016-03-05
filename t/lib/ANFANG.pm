package # hide from pauses
  ANFANG;

# load-time critical
BEGIN {
  if ( $ENV{RELEASE_TESTING} ) {
    require warnings and warnings->import;
    require strict and strict->import;
  }
}

#
# FROM THIS POINT ONWARD EVERYTHING HAPPENS LINEARLY AT RUNTIME
#
our $anfang_loaded;

# this allows the obscure but possible call case to behave correctly:
#
#   perl -Mt::lib::ANFANG -e 'do "./t/lib/ANFANG.pm" or die ( $@ || $! )'
#
return 1 if $anfang_loaded;

# cover even more bases
$INC{$_} ||= __FILE__ for (qw( ANFANG.pm t/lib/ANFANG.pm ./t/lib/ANFANG.pm ));

{
  # load-me-first sanity check
  if (

    # nobody shut us off
    ! $ENV{DBICTEST_ANFANG_DEFANG}

      and

    # if these are set - all bets are off
    ! (
      $ENV{PERL5OPT}
        or
      scalar grep { $_ =~ m| \/ sitecustomize\.pl $ |x } keys %INC
    )

      and

    # -d:Confess / -d:TraceUse and the like
    ! $^P

      and

    # just don't check anything under RELEASE_TESTING
    # a naive approach would be to simply whitelist both
    # strict and warnings, but pre 5.10 there were even
    # more modules loaded by these two:
    #
    #   perlbrew exec perl -Mstrict -Mwarnings -e 'warn join "\n", sort keys %INC'
    #
    ! $ENV{RELEASE_TESTING}

      and

    my @undesirables = grep {

      ($INC{$_}||'') ne __FILE__

        and

      # allow direct loads via -M
      $_ !~ m{^ DBICTest (?: /Schema )? \.pm $}x

    } keys %INC

  ) {

    my ( $fr, @frame );
    while (@frame = caller(++$fr)) {
      last if $frame[1] !~ m{ (?: \A | [\/\\] ) t [\/\\] lib [\/\\] }x;
    }

    die __FILE__ . " must be loaded before any other module (i.e. @{[ join ', ', map { qq('$_') } sort @undesirables ]}) at $frame[1] line $frame[2]\n";
  }


  if ( $ENV{DBICTEST_VERSION_WARNS_INDISCRIMINATELY} ) {
    my $ov = UNIVERSAL->can("VERSION");

    require Carp;

    # not loading warnings.pm
    local $^W = 0;

    *UNIVERSAL::VERSION = sub {
      Carp::carp( 'Argument "blah bleh bloh" isn\'t numeric in subroutine entry' );
      &$ov;
    };
  }


  if (
    $ENV{DBICTEST_ASSERT_NO_SPURIOUS_EXCEPTION_ACTION}
      or
    # keep it always on during CI
    (
      ($ENV{TRAVIS}||'') eq 'true'
        and
      ($ENV{TRAVIS_REPO_SLUG}||'') =~ m|\w+/dbix-class$|
    )
  ) {
    require Try::Tiny;
    my $orig = \&Try::Tiny::try;

    # not loading warnings.pm
    local $^W = 0;

    *Try::Tiny::try = sub (&;@) {
      my ($fr, $first_pkg) = 0;
      while( $first_pkg = caller($fr++) ) {
        last if $first_pkg !~ /^
          __ANON__
            |
          \Q(eval)\E
        $/x;
      }

      if ($first_pkg =~ /DBIx::Class/) {
        require Test::Builder;
        Test::Builder->new->ok(0,
          'Using try{} within DBIC internals is a mistake - use dbic_internal_try{} instead'
        );
      }

      goto $orig;
    };
  }
}


require lib;
lib->import('t/lib');


# everything expects this to be there
! -d 't/var' and (
  mkdir 't/var'
    or
  die "Unable to create 't/var': $!\n"
);


# Back in ab340f7f ribasushi stupidly introduced a "did you check your deps"
# verification tied very tightly to Module::Install. The check went away, and
# so eventually will M::I, but bisecting can bring all of this back from the
# dead. In order to reduce hair-pulling make sure that ./inc/ is always there
-f 'Makefile.PL' and mkdir 'inc' and mkdir 'inc/.author';

END {
  if( my @finalest_tasks = (

    ( !$ENV{DBICTEST_DIRTY_EXIT} ? () : sub {

      my $exit = $?;
      require POSIX;

      # Crucial flushes in case we are piping things out (e.g. prove)
      # Otherwise the last lines will never arrive at the receiver
      select($_), $| = 1 for \*STDOUT, \*STDERR;

      POSIX::_exit($exit);
    } ),

  )) {

    # in the case of an early skip_all B may very well not have loaded
    unless( $INC{"B.pm"} ) {
      local ( $!, $^E, $?, $@ );
      require B;
    }

    # Make sure we run after any cleanup in other END blocks
    # ( push-to-end twice in a row )
    push @{ B::end_av()->object_2svref }, sub {
      push @{ B::end_av()->object_2svref }, @finalest_tasks;
    }
  }
}

# make absolutely sure this is last
$anfang_loaded = 1;
