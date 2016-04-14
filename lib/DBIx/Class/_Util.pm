package # hide from PAUSE
  DBIx::Class::_Util;

use warnings;
use strict;

use constant SPURIOUS_VERSION_CHECK_WARNINGS => ( "$]" < 5.010 ? 1 : 0);

BEGIN {
  package # hide from pause
    DBIx::Class::_ENV_;

  use Config;

  use constant {

    # but of course
    BROKEN_FORK => ($^O eq 'MSWin32') ? 1 : 0,

    BROKEN_GOTO => ( "$]" < 5.008003 ) ? 1 : 0,

    HAS_ITHREADS => $Config{useithreads} ? 1 : 0,

    UNSTABLE_DOLLARAT => ( "$]" < 5.013002 ) ? 1 : 0,

    ( map
      #
      # the "DBIC_" prefix below is crucial - this is what makes CI pick up
      # all envvars without further adjusting its scripts
      # DO NOT CHANGE to the more logical { $_ => !!( $ENV{"DBIC_$_"} ) }
      #
      { substr($_, 5) => !!( $ENV{$_} ) }
      qw(
        DBIC_SHUFFLE_UNORDERED_RESULTSETS
        DBIC_ASSERT_NO_INTERNAL_WANTARRAY
        DBIC_ASSERT_NO_INTERNAL_INDIRECT_CALLS
        DBIC_STRESSTEST_UTF8_UPGRADE_GENERATED_COLLAPSER_SOURCE
        DBIC_STRESSTEST_COLUMN_INFO_UNAWARE_STORAGE
      )
    ),

    IV_SIZE => $Config{ivsize},

    OS_NAME => $^O,
  };

  if ( "$]" < 5.009_005) {
    require MRO::Compat;
    constant->import( OLD_MRO => 1 );
  }
  else {
    require mro;
    constant->import( OLD_MRO => 0 );
  }

  # Both of these are no longer used for anything. However bring
  # them back after they were purged in 08a8d8f1, as there appear
  # to be outfits with *COPY PASTED* pieces of lib/DBIx/Class/Storage/*
  # in their production codebases. There is no point in breaking these
  # if whatever they used actually continues to work
  my $warned;
  my $sigh = sub {

    require Carp;
    my $cluck = "The @{[ (caller(1))[3] ]} constant is no more - adjust your code" . Carp::longmess();

    warn $cluck unless $warned->{$cluck}++;

    0;
  };
  sub DBICTEST () { &$sigh }
  sub PEEPEENESS () { &$sigh }
}

# FIXME - this is not supposed to be here
# Carp::Skip to the rescue soon
use DBIx::Class::Carp '^DBIx::Class|^DBICTest';

use B ();
use Carp 'croak';
use Storable 'nfreeze';
use Scalar::Util qw(weaken blessed reftype refaddr);
use Sub::Quote qw(qsub quote_sub);

# Already correctly prototyped: perlbrew exec perl -MStorable -e 'warn prototype \&Storable::dclone'
BEGIN { *deep_clone = \&Storable::dclone }

use base 'Exporter';
our @EXPORT_OK = qw(
  sigwarn_silencer modver_gt_or_eq modver_gt_or_eq_and_lt
  fail_on_internal_wantarray fail_on_internal_call
  refdesc refcount hrefaddr
  scope_guard detected_reinvoked_destructor
  is_exception dbic_internal_try
  quote_sub qsub perlstring serialize deep_clone dump_value
  parent_dir mkdir_p
  UNRESOLVABLE_CONDITION
);

use constant UNRESOLVABLE_CONDITION => \ '1 = 0';

sub sigwarn_silencer ($) {
  my $pattern = shift;

  croak "Expecting a regexp" if ref $pattern ne 'Regexp';

  my $orig_sig_warn = $SIG{__WARN__} || sub { CORE::warn(@_) };

  return sub { &$orig_sig_warn unless $_[0] =~ $pattern };
}

sub perlstring ($) { q{"}. quotemeta( shift ). q{"} };

sub hrefaddr ($) { sprintf '0x%x', &refaddr||0 }

sub refdesc ($) {
  croak "Expecting a reference" if ! length ref $_[0];

  # be careful not to trigger stringification,
  # reuse @_ as a scratch-pad
  sprintf '%s%s(0x%x)',
    ( defined( $_[1] = blessed $_[0]) ? "$_[1]=" : '' ),
    reftype $_[0],
    refaddr($_[0]),
  ;
}

sub refcount ($) {
  croak "Expecting a reference" if ! length ref $_[0];

  # No tempvars - must operate on $_[0], otherwise the pad
  # will count as an extra ref
  B::svref_2object($_[0])->REFCNT;
}

sub serialize ($) {
  local $Storable::canonical = 1;
  nfreeze($_[0]);
}

my $dd_obj;
sub dump_value ($) {
  local $Data::Dumper::Indent = 1
    unless defined $Data::Dumper::Indent;

  my $dump_str = (
    $dd_obj
      ||=
    do {
      require Data::Dumper;
      my $d = Data::Dumper->new([])
        ->Purity(0)
        ->Pad('')
        ->Useqq(1)
        ->Terse(1)
        ->Freezer('')
        ->Quotekeys(0)
        ->Bless('bless')
        ->Pair(' => ')
        ->Sortkeys(1)
        ->Deparse(1)
      ;

      $d->Sparseseen(1) if modver_gt_or_eq (
        'Data::Dumper', '2.136'
      );

      $d;
    }
  )->Values([$_[0]])->Dump;

  $dd_obj->Reset->Values([]);

  $dump_str;
}

sub scope_guard (&) {
  croak 'Calling scope_guard() in void context makes no sense'
    if ! defined wantarray;

  # no direct blessing of coderefs - DESTROY is buggy on those
  bless [ $_[0] ], 'DBIx::Class::_Util::ScopeGuard';
}
{
  package #
    DBIx::Class::_Util::ScopeGuard;

  sub DESTROY {
    &DBIx::Class::_Util::detected_reinvoked_destructor;

    local $@ if DBIx::Class::_ENV_::UNSTABLE_DOLLARAT;

    eval {
      $_[0]->[0]->();
      1;
    }
      or
    Carp::cluck(
      "Execution of scope guard $_[0] resulted in the non-trappable exception:\n\n$@"
    );
  }
}


sub is_exception ($) {
  my $e = $_[0];

  # FIXME
  # this is not strictly correct - an eval setting $@ to undef
  # is *not* the same as an eval setting $@ to ''
  # but for the sake of simplicity assume the following for
  # the time being
  return 0 unless defined $e;

  my ($not_blank, $suberror);
  {
    local $SIG{__DIE__} if $SIG{__DIE__};
    local $@;
    eval {
      # The ne() here is deliberate - a plain length($e), or worse "$e" ne
      # will entirely obviate the need for the encolsing eval{}, as the
      # condition we guard against is a missing fallback overload
      $not_blank = ( $e ne '' );
      1;
    } or $suberror = $@;
  }

  if (defined $suberror) {
    if (length (my $class = blessed($e) )) {
      carp_unique( sprintf(
        'External exception class %s implements partial (broken) overloading '
      . 'preventing its instances from being used in simple ($x eq $y) '
      . 'comparisons. Given Perl\'s "globally cooperative" exception '
      . 'handling this type of brokenness is extremely dangerous on '
      . 'exception objects, as it may (and often does) result in silent '
      . '"exception substitution". DBIx::Class tries to work around this '
      . 'as much as possible, but other parts of your software stack may '
      . 'not be even aware of this. Please submit a bugreport against the '
      . 'distribution containing %s and in the meantime apply a fix similar '
      . 'to the one shown at %s, in order to ensure your exception handling '
      . 'is saner application-wide. What follows is the actual error text '
      . "as generated by Perl itself:\n\n%s\n ",
        $class,
        $class,
        'http://v.gd/DBIC_overload_tempfix/',
        $suberror,
      ));

      # workaround, keeps spice flowing
      $not_blank = !!( length $e );
    }
    else {
      # not blessed yet failed the 'ne'... this makes 0 sense...
      # just throw further
      die $suberror
    }
  }
  elsif (
    # a ref evaluating to '' is definitively a "null object"
    ( not $not_blank )
      and
    length( my $class = ref $e )
  ) {
    carp_unique( sprintf(
      "Objects of external exception class '%s' stringify to '' (the "
    . 'empty string), implementing the so called null-object-pattern. '
    . 'Given Perl\'s "globally cooperative" exception handling using this '
    . 'class of exceptions is extremely dangerous, as it may (and often '
    . 'does) result in silent discarding of errors. DBIx::Class tries to '
    . 'work around this as much as possible, but other parts of your '
    . 'software stack may not be even aware of the problem. Please submit '
    . 'a bugreport against the distribution containing %s',

      ($class) x 2,
    ));

    $not_blank = 1;
  }

  return $not_blank;
}

{
  my $callstack_state;

  # Recreate the logic of try(), while reusing the catch()/finally() as-is
  #
  # FIXME: We need to move away from Try::Tiny entirely (way too heavy and
  # yes, shows up ON TOP of profiles) but this is a batle for another maint
  sub dbic_internal_try (&;@) {

    my $try_cref = shift;
    my $catch_cref = undef;  # apparently this is a thing... https://rt.perl.org/Public/Bug/Display.html?id=119311

    for my $arg (@_) {

      if( ref($arg) eq 'Try::Tiny::Catch' ) {

        croak 'dbic_internal_try() may not be followed by multiple catch() blocks'
          if $catch_cref;

        $catch_cref = $$arg;
      }
      elsif ( ref($arg) eq 'Try::Tiny::Finally' ) {
        croak 'dbic_internal_try() does not support finally{}';
      }
      else {
        croak(
          'dbic_internal_try() encountered an unexpected argument '
        . "'@{[ defined $arg ? $arg : 'UNDEF' ]}' - perhaps "
        . 'a missing semi-colon before or ' # trailing space important
        );
      }
    }

    my $wantarray = wantarray;
    my $preexisting_exception = $@;

    my @ret;
    my $all_good = eval {
      $@ = $preexisting_exception;

      local $callstack_state->{in_internal_try} = 1
        unless $callstack_state->{in_internal_try};

      # always unset - someone may have snuck it in
      local $SIG{__DIE__} if $SIG{__DIE__};

      if( $wantarray ) {
        @ret = $try_cref->();
      }
      elsif( defined $wantarray ) {
        $ret[0] = $try_cref->();
      }
      else {
        $try_cref->();
      }

      1;
    };

    my $exception = $@;
    $@ = $preexisting_exception;

    if ( $all_good ) {
      return $wantarray ? @ret : $ret[0]
    }
    elsif ( $catch_cref ) {
      for ( $exception ) {
        return $catch_cref->($exception);
      }
    }

    return;
  }

  sub in_internal_try { !! $callstack_state->{in_internal_try} }
}

{
  my $destruction_registry = {};

  sub CLONE {
    $destruction_registry = { map
      { defined $_ ? ( refaddr($_) => $_ ) : () }
      values %$destruction_registry
    };

    weaken( $destruction_registry->{$_} )
      for keys %$destruction_registry;

    # Dummy NEXTSTATE ensuring the all temporaries on the stack are garbage
    # collected before leaving this scope. Depending on the code above, this
    # may very well be just a preventive measure guarding future modifications
    undef;
  }

  # This is almost invariably invoked from within DESTROY
  # throwing exceptions won't work
  sub detected_reinvoked_destructor {

    # quick "garbage collection" pass - prevents the registry
    # from slowly growing with a bunch of undef-valued keys
    defined $destruction_registry->{$_} or delete $destruction_registry->{$_}
      for keys %$destruction_registry;

    if (! length ref $_[0]) {
      printf STDERR '%s() expects a blessed reference %s',
        (caller(0))[3],
        Carp::longmess,
      ;
      return undef; # don't know wtf to do
    }
    elsif (! defined $destruction_registry->{ my $addr = refaddr($_[0]) } ) {
      weaken( $destruction_registry->{$addr} = $_[0] );
      return 0;
    }
    else {
      carp_unique ( sprintf (
        'Preventing *MULTIPLE* DESTROY() invocations on %s - an *EXTREMELY '
      . 'DANGEROUS* condition which is *ALMOST CERTAINLY GLOBAL* within your '
      . 'application, affecting *ALL* classes without active protection against '
      . 'this. Diagnose and fix the root cause ASAP!!!%s',
      refdesc $_[0],
        ( ( $INC{'Devel/StackTrace.pm'} and ! do { local $@; eval { Devel::StackTrace->VERSION(2) } } )
          ? " (likely culprit Devel::StackTrace\@@{[ Devel::StackTrace->VERSION ]} found in %INC, http://is.gd/D_ST_refcap)"
          : ''
        )
      ));

      return 1;
    }
  }
}

my $module_name_rx = qr/ \A [A-Z_a-z] [0-9A-Z_a-z]* (?: :: [0-9A-Z_a-z]+ )* \z /x;
my $ver_rx =         qr/ \A [0-9]+ (?: \. [0-9]+ )* (?: \_ [0-9]+ )*        \z /x;

sub modver_gt_or_eq ($$) {
  my ($mod, $ver) = @_;

  croak "Nonsensical module name supplied"
    if ! defined $mod or $mod !~ $module_name_rx;

  croak "Nonsensical minimum version supplied"
    if ! defined $ver or $ver !~ $ver_rx;

  no strict 'refs';
  my $ver_cache = ${"${mod}::__DBIC_MODULE_VERSION_CHECKS__"} ||= ( $mod->VERSION
    ? {}
    : croak "$mod does not seem to provide a version (perhaps it never loaded)"
  );

  ! defined $ver_cache->{$ver}
    and
  $ver_cache->{$ver} = do {

    local $SIG{__WARN__} = sigwarn_silencer( qr/\Qisn't numeric in subroutine entry/ )
      if SPURIOUS_VERSION_CHECK_WARNINGS;

    local $SIG{__DIE__} if $SIG{__DIE__};
    local $@;
    eval { $mod->VERSION($ver) } ? 1 : 0;
  };

  $ver_cache->{$ver};
}

sub modver_gt_or_eq_and_lt ($$$) {
  my ($mod, $v_ge, $v_lt) = @_;

  croak "Nonsensical maximum version supplied"
    if ! defined $v_lt or $v_lt !~ $ver_rx;

  return (
    modver_gt_or_eq($mod, $v_ge)
      and
    ! modver_gt_or_eq($mod, $v_lt)
  ) ? 1 : 0;
}


#
# Why not just use some higher-level module or at least File::Spec here?
# Because:
# 1)  This is a *very* rarely used function, and the deptree is large
#     enough already as it is
#
# 2)  (more importantly) Our tooling is utter shit in this area. There
#     is no comprehensive support for UNC paths in PathTools and there
#     are also various small bugs in representation across different
#     path-manipulation CPAN offerings.
#
# Since this routine is strictly used for logical path processing (it
# *must* be able to work with not-yet-existing paths), use this seemingly
# simple but I *think* complete implementation to feed to other consumers
#
# If bugs are ever uncovered in this routine, *YOU ARE URGED TO RESIST*
# the impulse to bring in an external dependency. During runtime there
# is exactly one spot that could potentially maybe once in a blue moon
# use this function. Keep it lean.
#
sub parent_dir ($) {
  ( $_[0] =~ m{  [\/\\]  ( \.{0,2} ) ( [\/\\]* ) \z }x )
    ? (
      $_[0]
        .
      ( ( length($1) and ! length($2) ) ? '/' : '' )
        .
      '../'
    )
    : (
      require File::Spec
        and
      File::Spec->catpath (
        ( File::Spec->splitpath( "$_[0]" ) )[0,1],
        '/',
      )
    )
  ;
}

sub mkdir_p ($) {
  require File::Path;
  # do not ask for a recent version, use 1.x API calls
  File::Path::mkpath([ "$_[0]" ]);  # File::Path does not like objects
}


{
  my $list_ctx_ok_stack_marker;

  sub fail_on_internal_wantarray () {
    return if $list_ctx_ok_stack_marker;

    if (! defined wantarray) {
      croak('fail_on_internal_wantarray() needs a tempvar to save the stack marker guard');
    }

    my $cf = 1;
    while ( ( (CORE::caller($cf+1))[3] || '' ) =~ / :: (?:

      # these are public API parts that alter behavior on wantarray
      search | search_related | slice | search_literal

        |

      # these are explicitly prefixed, since we only recognize them as valid
      # escapes when they come from the guts of CDBICompat
      CDBICompat .*? :: (?: search_where | retrieve_from_sql | retrieve_all )

    ) $/x ) {
      $cf++;
    }

    my ($fr, $want, $argdesc);
    {
      package DB;
      $fr = [ CORE::caller($cf) ];
      $want = ( CORE::caller($cf-1) )[5];
      $argdesc = ref $DB::args[0]
        ? DBIx::Class::_Util::refdesc($DB::args[0])
        : 'non '
      ;
    };

    if (
      $want and $fr->[0] =~ /^(?:DBIx::Class|DBICx::)/
    ) {
      DBIx::Class::Exception->throw( sprintf (
        "Improper use of %s instance in list context at %s line %d\n\n    Stacktrace starts",
        $argdesc, @{$fr}[1,2]
      ), 'with_stacktrace');
    }

    my $mark = [];
    weaken ( $list_ctx_ok_stack_marker = $mark );
    $mark;
  }
}

sub fail_on_internal_call {
  my ($fr, $argdesc);
  {
    package DB;
    $fr = [ CORE::caller(1) ];
    $argdesc = ref $DB::args[0]
      ? DBIx::Class::_Util::refdesc($DB::args[0])
      : undef
    ;
  };

  if (
    $argdesc
      and
    $fr->[0] =~ /^(?:DBIx::Class|DBICx::)/
      and
    $fr->[1] !~ /\b(?:CDBICompat|ResultSetProxy)\b/  # no point touching there
  ) {
    DBIx::Class::Exception->throw( sprintf (
      "Illegal internal call of indirect proxy-method %s() with argument %s: examine the last lines of the proxy method deparse below to determine what to call directly instead at %s on line %d\n\n%s\n\n    Stacktrace starts",
      $fr->[3], $argdesc, @{$fr}[1,2], ( $fr->[6] || do {
        require B::Deparse;
        no strict 'refs';
        B::Deparse->new->coderef2text(\&{$fr->[3]})
      }),
    ), 'with_stacktrace');
  }
}

1;
