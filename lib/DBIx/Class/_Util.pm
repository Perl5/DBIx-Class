package # hide from PAUSE
  DBIx::Class::_Util;

# load es early as we can, usually a noop
use DBIx::Class::StartupCheck;

use warnings;
use strict;

# For the love of everything that is crab-like: DO NOT reach into this
# The entire thing is really fragile and should not be screwed with
# unless absolutely and unavoidably necessary
our $__describe_class_query_cache;

BEGIN {
  package # hide from pause
    DBIx::Class::_ENV_;

  use Config;

  use constant {
    PERL_VERSION => "$]",
    OS_NAME => "$^O",
  };

  use constant {

    # but of course
    BROKEN_FORK => (OS_NAME eq 'MSWin32') ? 1 : 0,

    BROKEN_GOTO => ( PERL_VERSION < 5.008003 ) ? 1 : 0,

    # perl -MScalar::Util=weaken -e 'weaken( $hash{key} = \"value" )'
    BROKEN_WEAK_SCALARREF_VALUES => ( PERL_VERSION < 5.008003 ) ? 1 : 0,

    HAS_ITHREADS => $Config{useithreads} ? 1 : 0,

    TAINT_MODE => 0 + ${^TAINT}, # tri-state: 0, 1, -1

    UNSTABLE_DOLLARAT => ( PERL_VERSION < 5.013002 ) ? 1 : 0,

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
        DBIC_ASSERT_NO_ERRONEOUS_METAINSTANCE_USE
        DBIC_ASSERT_NO_FAILING_SANITY_CHECKS
        DBIC_STRESSTEST_UTF8_UPGRADE_GENERATED_COLLAPSER_SOURCE
        DBIC_STRESSTEST_COLUMN_INFO_UNAWARE_STORAGE
      )
    ),

    IV_SIZE => $Config{ivsize},
  };

  if ( PERL_VERSION < 5.009_005) {
    require MRO::Compat;
    constant->import( OLD_MRO => 1 );

    #
    # Yes, I know this is a rather PHP-ish name, but please first read
    # https://metacpan.org/source/BOBTFISH/MRO-Compat-0.12/lib/MRO/Compat.pm#L363-368
    #
    # Even if we are using Class::C3::XS it still won't work, as doing
    #   defined( *{ "SubClass::"->{$_} }{CODE} )
    # will set pkg_gen to the same value for SubClass and *ALL PARENTS*
    #
    *DBIx::Class::_Util::get_real_pkg_gen = sub ($) {
      require Digest::MD5;
      require Math::BigInt;

      my $cur_class;
      no strict 'refs';

      # the non-assign-unless-there-is-a-hash is deliberate
      ( $__describe_class_query_cache->{'!internal!'} || {} )->{$_[0]}{gen} ||= (
        Math::BigInt->new( '0x' . ( Digest::MD5::md5_hex( join "\0", map {

          ( $__describe_class_query_cache->{'!internal!'} || {} )->{$_}{methlist} ||= (

            $cur_class = $_

              and

            # RV to be hashed up and turned into a number
            join "\0", (
              $cur_class,
              map
                {(
                  # stringification should be sufficient, ignore names/refaddr entirely
                  $_,
                  do {
                    my @attrs;
                    local $@;
                    local $SIG{__DIE__} if $SIG{__DIE__};
                    # attributes::get may throw on blessed-false crefs :/
                    eval { @attrs = attributes::get( $_ ); 1 }
                      or warn "Unable to determine attributes of coderef $_ due to the following error: $@";
                    @attrs;
                  },
                )}
                map
                  {(
                    # skip dummy C::C3 helper crefs
                    ! ( ( $Class::C3::MRO{$cur_class} || {} )->{methods}{$_} )
                      and
                    (
                      ref(\ "${cur_class}::"->{$_} ) ne 'GLOB'
                        or
                      defined( *{ "${cur_class}::"->{$_} }{CODE} )
                    )
                  )
                    ? ( \&{"${cur_class}::$_"} )
                    : ()
                  }
                  keys %{ "${cur_class}::" }
            )
          )
        } (

          @{
            ( $__describe_class_query_cache->{'!internal!'} || {} )->{$_[0]}{linear_isa}
              ||=
            mro::get_linear_isa($_[0])
          },

          ((
            ( $__describe_class_query_cache->{'!internal!'} || {} )->{$_[0]}{is_universal}
              ||=
            mro::is_universal($_[0])
          ) ? () : @{
            ( $__describe_class_query_cache->{'!internal!'} || {} )->{UNIVERSAL}{linear_isa}
              ||=
            mro::get_linear_isa("UNIVERSAL")
          } ),

        ) ) ) )
      );
    };
  }
  else {
    require mro;
    constant->import( OLD_MRO => 0 );
    *DBIx::Class::_Util::get_real_pkg_gen = \&mro::get_pkg_gen;
  }

  # Both of these are no longer used for anything. However bring
  # them back after they were purged in 08a8d8f1, as there appear
  # to be outfits with *COPY PASTED* pieces of lib/DBIx/Class/Storage/*
  # in their production codebases. There is no point in breaking these
  # if whatever they used actually continues to work
  my $sigh = sub {
    DBIx::Class::_Util::emit_loud_diag(
      skip_frames => 1,
      msg => "The @{[ (caller(1))[3] ]} constant is no more - adjust your code"
    );

    0;
  };
  sub DBICTEST () { &$sigh }
  sub PEEPEENESS () { &$sigh }
}

use constant SPURIOUS_VERSION_CHECK_WARNINGS => ( DBIx::Class::_ENV_::PERL_VERSION < 5.010 ? 1 : 0);

# FIXME - this is not supposed to be here
# Carp::Skip to the rescue soon
use DBIx::Class::Carp '^DBIx::Class|^DBICTest';

# Ensure it is always there, in case we need to do a $schema-less throw()
use DBIx::Class::Exception ();

use B ();
use Carp 'croak';
use Storable 'nfreeze';
use Scalar::Util qw(weaken blessed reftype refaddr);
use Sub::Name ();
use attributes ();

# Usually versions are not specified anywhere aside the Makefile.PL
# (writing them out in-code is extremely obnoxious)
# However without a recent enough Moo the quote_sub override fails
# in very puzzling and hard to detect ways: so add a version check
# just this once
use Sub::Quote qw(qsub);
BEGIN { Sub::Quote->VERSION('2.002002') }

# Already correctly prototyped: perlbrew exec perl -MStorable -e 'warn prototype \&Storable::dclone'
BEGIN { *deep_clone = \&Storable::dclone }

use base 'Exporter';
our @EXPORT_OK = qw(
  sigwarn_silencer modver_gt_or_eq modver_gt_or_eq_and_lt
  fail_on_internal_wantarray fail_on_internal_call
  refdesc refcount hrefaddr set_subname get_subname describe_class_methods
  scope_guard detected_reinvoked_destructor emit_loud_diag
  true false
  is_exception dbic_internal_try dbic_internal_catch visit_namespaces
  quote_sub qsub perlstring serialize deep_clone dump_value uniq
  parent_dir mkdir_p
  UNRESOLVABLE_CONDITION DUMMY_ALIASPAIR
);

use constant UNRESOLVABLE_CONDITION => \ '1 = 0';

use constant DUMMY_ALIASPAIR => (
  foreign_alias => "!!!\xFF()!!!_DUMMY_FOREIGN_ALIAS_SHOULD_NEVER_BE_SEEN_IN_USE_!!!()\xFF!!!",
  self_alias => "!!!\xFE()!!!_DUMMY_SELF_ALIAS_SHOULD_NEVER_BE_SEEN_IN_USE_!!!()\xFE!!!",
);

# Override forcing no_defer, and adding naming consistency checks
our %refs_closed_over_by_quote_sub_installed_crefs;
sub quote_sub {
  Carp::confess( "Anonymous quoting not supported by the DBIC quote_sub override - supply a sub name" ) if
    @_ < 2
      or
    ! defined $_[1]
      or
    length ref $_[1]
  ;

  Carp::confess( "The DBIC quote_sub override expects sub name '$_[0]' to be fully qualified" )
    unless (my $stash) = $_[0] =~ /^(.+)::/;

  Carp::confess(
    "The DBIC sub_quote override does not support 'no_install'"
  ) if (
    $_[3]
      and
    $_[3]->{no_install}
  );

  Carp::confess(
    'The DBIC quote_sub override expects the namespace-part of sub name '
  . "'$_[0]' to match the supplied package argument '$_[3]->{package}'"
  ) if (
    $_[3]
      and
    defined $_[3]->{package}
      and
    $stash ne $_[3]->{package}
  );

  my @caller = caller(0);
  my $sq_opts = {
    package => $caller[0],
    hints => $caller[8],
    warning_bits => $caller[9],
    hintshash => $caller[10],
    %{ $_[3] || {} },

    # explicitly forced for everything
    no_defer => 1,
  };

  weaken (
    # just use a growing counter, no need to perform neither compaction
    # nor any special ithread-level handling
    $refs_closed_over_by_quote_sub_installed_crefs
     { scalar keys %refs_closed_over_by_quote_sub_installed_crefs }
      = $_
  ) for grep {
    length ref $_
      and
    (
      ! DBIx::Class::_ENV_::BROKEN_WEAK_SCALARREF_VALUES
        or
      ref $_ ne 'SCALAR'
    )
  } values %{ $_[2] || {} };

  Sub::Quote::quote_sub( $_[0], $_[1], $_[2]||{}, $sq_opts );
}

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

sub visit_namespaces {
  my $args = { (ref $_[0]) ? %{$_[0]} : @_ };

  my $visited_count = 1;

  # A package and a namespace are subtly different things
  $args->{package} ||= 'main';
  $args->{package} = 'main' if $args->{package} =~ /^ :: (?: main )? $/x;
  $args->{package} =~ s/^:://;

  if ( $args->{action}->($args->{package}) ) {
    my $ns =
      ( ($args->{package} eq 'main') ? '' :  $args->{package} )
        .
      '::'
    ;

    $visited_count += visit_namespaces( %$args, package => $_ ) for
      grep
        # this happens sometimes on %:: traversal
        { $_ ne '::main' }
        map
          { $_ =~ /^(.+?)::$/ ? "$ns$1" : () }
          do { no strict 'refs'; keys %$ns }
    ;
  }

  $visited_count;
}

# FIXME In another life switch these to a polyfill like the ones in namespace::clean
sub get_subname ($) {
  my $gv = B::svref_2object( $_[0] )->GV;
  wantarray
    ? ( $gv->STASH->NAME, $gv->NAME )
    : ( join '::', $gv->STASH->NAME, $gv->NAME )
  ;
}
sub set_subname ($$) {

  # fully qualify name
  splice @_, 0, 1, caller(0) . "::$_[0]"
    if $_[0] !~ /::|'/;

  &Sub::Name::subname;
}

sub serialize ($) {
  # stable hash order
  local $Storable::canonical = 1;

  # explicitly false - there is nothing sensible that can come out of
  # an attempt at CODE serialization
  local $Storable::Deparse;

  # take no chances
  local $Storable::forgive_me;

  # FIXME
  # A number of codepaths *expect* this to be Storable.pm-based so that
  # the STORABLE_freeze hooks in the metadata subtree get executed properly
  nfreeze($_[0]);
}

sub uniq {
  my( %seen, $seen_undef, $numeric_preserving_copy );
  grep { not (
    defined $_
      ? $seen{ $numeric_preserving_copy = $_ }++
      : $seen_undef++
  ) } @_;
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

      # FIXME - this is kinda ridiculous - there ought to be a
      # Data::Dumper->new_with_defaults or somesuch...
      #
      if( modver_gt_or_eq ( 'Data::Dumper', '2.136' ) ) {
        $d->Sparseseen(1);

        if( modver_gt_or_eq ( 'Data::Dumper', '2.153' ) ) {
          $d->Maxrecurse(1000);

          if( modver_gt_or_eq ( 'Data::Dumper', '2.160' ) ) {
            $d->Trailingcomma(1);
          }
        }
      }

      $d;
    }
  )->Values([$_[0]])->Dump;

  $dd_obj->Reset->Values([]);

  $dump_str;
}

my $seen_loud_screams;
sub emit_loud_diag {
  my $args = { ref $_[0] eq 'HASH' ? %{$_[0]} : @_ };

  unless ( defined $args->{msg} and length $args->{msg} ) {
    emit_loud_diag(
      msg => "No 'msg' value supplied to emit_loud_diag()"
    );
    exit 70;
  }

  my $msg = "\n" . join( ': ',
    ( $0 eq '-e' ? () : $0 ),
    $args->{msg}
  );

  # when we die - we usually want to keep doing it
  $args->{emit_dups} = !!$args->{confess}
    unless exists $args->{emit_dups};

  local $Carp::CarpLevel =
    ( $args->{skip_frames} || 0 )
      +
    $Carp::CarpLevel
      +
    # hide our own frame
    1
  ;

  my $longmess = Carp::longmess();

  # different object references will thwart deduplication without this
  ( my $key = "${msg}\n${longmess}" ) =~ s/\b0x[0-9a-f]+\b/0x.../gi;

  return $seen_loud_screams->{$key} if
    $seen_loud_screams->{$key}++
      and
    ! $args->{emit_dups}
  ;

  $msg .= $longmess
    unless $msg =~ /\n\z/;

  print STDERR "$msg\n"
    or
  print STDOUT "\n!!!STDERR ISN'T WRITABLE!!!:$msg\n";

  return $seen_loud_screams->{$key}
    unless $args->{confess};

  # increment *again*, because... Carp.
  $Carp::CarpLevel++;

  # not $msg - Carp will reapply the longmess on its own
  Carp::confess($args->{msg});
}


###
### This is *NOT* boolean.pm - deliberately not using a singleton
###
{
  package # hide from pause
    DBIx::Class::_Util::_Bool;
  use overload
    bool => sub { ${$_[0]} },
    fallback => 1,
  ;
}
sub true () { my $x = 1; bless \$x, "DBIx::Class::_Util::_Bool" }
sub false () { my $x = 0; bless \$x, "DBIx::Class::_Util::_Bool" }

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
    DBIx::Class::_Util::emit_loud_diag(
      emit_dups => 1,
      msg => "Execution of scope guard $_[0] resulted in the non-trappable exception:\n\n$@\n "
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
    carp_unique(
      "Objects of external exception class '$class' stringify to '' (the "
    . 'empty string), implementing the so called null-object-pattern. '
    . 'Given Perl\'s "globally cooperative" exception handling using this '
    . 'class of exceptions is extremely dangerous, as it may (and often '
    . 'does) result in silent discarding of errors. DBIx::Class tries to '
    . 'work around this as much as possible, but other parts of your '
    . 'software stack may not be even aware of the problem. Please submit '
    . "a bugreport against the distribution containing '$class'",
    );

    $not_blank = 1;
  }

  return $not_blank;
}

{
  my $callstack_state;

  # Recreate the logic of Try::Tiny, but without the crazy Sub::Name
  # invocations and without support for finally() altogether
  # ( yes, these days Try::Tiny is so "tiny" it shows *ON TOP* of most
  #   random profiles https://youtu.be/PYCbumw0Fis?t=1919 )
  sub dbic_internal_try (&;@) {

    my $try_cref = shift;
    my $catch_cref = undef;  # apparently this is a thing... https://rt.perl.org/Public/Bug/Display.html?id=119311

    for my $arg (@_) {

      croak 'dbic_internal_try() may not be followed by multiple dbic_internal_catch() blocks'
        if $catch_cref;

      ($catch_cref = $$arg), next
        if ref($arg) eq 'DBIx::Class::_Util::Catch';

      croak( 'Mixing dbic_internal_try() with Try::Tiny::catch() is not supported' )
        if ref($arg) eq 'Try::Tiny::Catch';

      croak( 'dbic_internal_try() does not support finally{}' )
        if ref($arg) eq 'Try::Tiny::Finally';

      croak(
        'dbic_internal_try() encountered an unexpected argument '
      . "'@{[ defined $arg ? $arg : 'UNDEF' ]}' - perhaps "
      . 'a missing semi-colon before or ' # trailing space important
      );
    }

    my $wantarray = wantarray;
    my $preexisting_exception = $@;

    my @ret;
    my $saul_goodman = eval {
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

    if ( $saul_goodman ) {
      return $wantarray ? @ret : $ret[0]
    }
    elsif ( $catch_cref ) {
      for ( $exception ) {
        return $catch_cref->($exception);
      }
    }

    return;
  }

  sub dbic_internal_catch (&;@) {

    croak( 'Useless use of bare dbic_internal_catch()' )
      unless wantarray;

    croak( 'dbic_internal_catch() must receive exactly one argument at end of expression' )
      if @_ > 1;

    bless(
      \( $_[0] ),
      'DBIx::Class::_Util::Catch'
    ),
  }

  sub in_internal_try () {
    !! $callstack_state->{in_internal_try}
  }
}

{
  my $destruction_registry = {};

  sub DBIx::Class::__Util_iThreads_handler__::CLONE {
    %$destruction_registry = map {
      (defined $_)
        ? ( refaddr($_) => $_ )
        : ()
    } values %$destruction_registry;

    weaken($_) for values %$destruction_registry;

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
      emit_loud_diag(
        emit_dups => 1,
        msg => (caller(0))[3] . '() expects a blessed reference'
      );
      return undef; # don't know wtf to do
    }
    elsif (! defined $destruction_registry->{ my $addr = refaddr($_[0]) } ) {
      weaken( $destruction_registry->{$addr} = $_[0] );
      return 0;
    }
    else {
      emit_loud_diag( msg => sprintf (
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

  my $ver_cache = do {
    no strict 'refs';
    ${"${mod}::__DBIC_MODULE_VERSION_CHECKS__"} ||= {}
  };

  ! defined $ver_cache->{$ver}
    and
  $ver_cache->{$ver} = do {

    local $SIG{__WARN__} = sigwarn_silencer( qr/\Qisn't numeric in subroutine entry/ )
      if SPURIOUS_VERSION_CHECK_WARNINGS;

    # prevent captures by potential __WARN__ hooks or the like:
    # there is nothing of value that can be happening here, and
    # leaving a hook in-place can only serve to fail some test
    local $SIG{__WARN__} if (
      ! SPURIOUS_VERSION_CHECK_WARNINGS
        and
      $SIG{__WARN__}
    );

    croak "$mod does not seem to provide a version (perhaps it never loaded)"
      unless $mod->VERSION;

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

{

  sub describe_class_methods {
    my $args = (
      ref $_[0] eq 'HASH'                 ? $_[0]
    : ( @_ == 1 and ! length ref $_[0] )  ? { class => $_[0] }
    :                                       { @_ }
    );

    my ($class, $requested_mro) = @{$args}{qw( class use_mro )};

    croak "Expecting a class name either as the sole argument or a 'class' option"
      if not defined $class or $class !~ $module_name_rx;

    croak(
      "The supplied 'class' argument is tainted: this is *extremely* "
    . 'dangerous, fix your code ASAP!!! ( for more details read through '
    . 'https://is.gd/perl_mro_taint_wtf )'
    ) if (
      DBIx::Class::_ENV_::TAINT_MODE
        and
      Scalar::Util::tainted($class)
    );

    $requested_mro ||= mro::get_mro($class);

    # mro::set_mro() does not bump pkg_gen - WHAT THE FUCK?!
    my $query_cache_key = "$class|$requested_mro";

    my $internal_cache_key =
      ( mro::get_mro($class) eq $requested_mro )
        ? $class
        : $query_cache_key
    ;

    # use a cache on old MRO, since while we are recursing in this function
    # nothing can possibly change (the speedup is immense)
    # (yes, people could be tie()ing the stash and adding methods on access
    # but there is a limit to how much crazy can be supported here)
    #
    # we use the cache for linear_isa lookups on new MRO as well - it adds
    # a *tiny* speedup, and simplifies the code a lot
    #
    local $__describe_class_query_cache->{'!internal!'} = {}
      unless $__describe_class_query_cache->{'!internal!'};

    my $my_gen = 0;

    $my_gen += get_real_pkg_gen($_) for ( my @full_ISA = (

      @{
        $__describe_class_query_cache->{'!internal!'}{$internal_cache_key}{linear_isa}
          ||=
        mro::get_linear_isa($class, $requested_mro)
      },

      ((
        $__describe_class_query_cache->{'!internal!'}{$class}{is_universal}
          ||=
        mro::is_universal($class)
      ) ? () : @{
        $__describe_class_query_cache->{'!internal!'}{UNIVERSAL}{linear_isa}
          ||=
        mro::get_linear_isa("UNIVERSAL")
      }),

    ));

    my $slot = $__describe_class_query_cache->{$query_cache_key} ||= {};

    unless ( ($slot->{cumulative_gen}||0) == $my_gen ) {

      # reset
      %$slot = (
        class => $class,
        isa => { map { $_ => 1 } @full_ISA },
        linear_isa => [
          @{ $__describe_class_query_cache->{'!internal!'}{$internal_cache_key}{linear_isa} }
            [ 1 .. $#{$__describe_class_query_cache->{'!internal!'}{$internal_cache_key}{linear_isa}} ]
        ],
        mro => {
          type => $requested_mro,
          is_c3 => ( ($requested_mro eq 'c3') ? 1 : 0 ),
        },
        cumulative_gen => $my_gen,
      );

      # remove ourselves from ISA
      shift @full_ISA;

      # ensure the cache is populated for the parents, code below can then
      # efficiently operate over the query_cache directly
      describe_class_methods($_) for reverse @full_ISA;

      no strict 'refs';

      # combine full ISA-order inherited and local method list into a
      # "shadowing stack"

      (
        unshift @{ $slot->{methods}{$_->{name}} }, $_

          and

        (
          $_->{via_class} ne $class
            or
          $slot->{methods_defined_in_class}{$_->{name}} = $_
        )

          and

        @{ $slot->{methods}{$_->{name}} } > 1

          and

        $slot->{methods_with_supers}{$_->{name}} = $slot->{methods}{$_->{name}}

      ) for (

        # what describe_class_methods for @full_ISA produced above
        ( map { values %{
          $__describe_class_query_cache->{$_}{methods_defined_in_class} || {}
        } } map { "$_|" . mro::get_mro($_) } reverse @full_ISA ),

        # our own non-cleaned subs + their attributes
        ( map {
          (
            # need to account for dummy helper crefs under OLD_MRO
            (
              ! DBIx::Class::_ENV_::OLD_MRO
                or
              ! ( ( $Class::C3::MRO{$class} || {} )->{methods}{$_} )
            )
              and
            # these 2 OR-ed checks are sufficient for 5.10+
            (
              ref(\ "${class}::"->{$_} ) ne 'GLOB'
                or
              defined( *{ "${class}::"->{$_} }{CODE} )
            )
          ) ? {
              via_class => $class,
              name => $_,
              attributes => { map { $_ => 1 } do {
                my @attrs;
                local $@;
                local $SIG{__DIE__} if $SIG{__DIE__};
                # attributes::get may throw on blessed-false crefs :/
                eval { @attrs = attributes::get( \&{"${class}::${_}"} ); 1 }
                  or warn "Unable to determine attributes of the \\&${class}::$_ method due to following error: $@";
                @attrs;
              } },
            }
            : ()
        } keys %{"${class}::"} )
      );


      # recalculate the pkg_gen on newer perls under Taint mode,
      # because of shit like:
      # perl -T -Mmro -e 'package Foo; sub bar {}; defined( *{ "Foo::"->{bar}}{CODE} ) and warn mro::get_pkg_gen("Foo") for (1,2,3)'
      #
      if (
        ! DBIx::Class::_ENV_::OLD_MRO
          and
        DBIx::Class::_ENV_::TAINT_MODE
      ) {

        $slot->{cumulative_gen} = 0;
        $slot->{cumulative_gen} += get_real_pkg_gen($_)
          for $class, @full_ISA;
      }
    }

    # RV
    +{ %$slot };
  }
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

    weaken( $list_ctx_ok_stack_marker = my $mark = [] );

    $mark;
  }
}

sub fail_on_internal_call {
  my ($fr, $argdesc);
  {
    package DB;
    $fr = [ CORE::caller(1) ];
    $argdesc =
      ( not defined $DB::args[0] )  ? 'UNAVAILABLE'
    : ( length ref $DB::args[0] )   ? DBIx::Class::_Util::refdesc($DB::args[0])
    : $DB::args[0] . ''
    ;
  };

  my @fr2;
  # need to make allowance for a proxy-yet-direct call
  my $check_fr = (
    $fr->[0] eq 'DBIx::Class::ResultSourceProxy'
      and
    @fr2 = (CORE::caller(2))
      and
    (
      ( $fr->[3] =~ /([^:])+$/ )[0]
        eq
      ( $fr2[3] =~ /([^:])+$/ )[0]
    )
  )
    ? \@fr2
    : $fr
  ;


  die "\nMethod $fr->[3] is not marked with the 'DBIC_method_is_indirect_sugar' attribute\n\n" unless (

    # unlikely but who knows...
    ! @$fr

      or

    # This is a weird-ass double-purpose method, only one branch of which is marked
    # as an illegal indirect call
    # Hence the 'indirect' attribute makes no sense
    # FIXME - likely need to mark this in some other manner
    $fr->[3] eq 'DBIx::Class::ResultSet::new'

      or

    # RsrcProxy stuff is special and not attr-annotated on purpose
    # Yet it is marked (correctly) as fail_on_internal_call(), as DBIC
    # itself should not call these methods as first-entry
    $fr->[3] =~ /^DBIx::Class::ResultSourceProxy::[^:]+$/

      or

    # FIXME - there is likely a more fine-graned way to escape "foreign"
    # callers, based on annotations... (albeit a slower one)
    # For the time being just skip in a dumb way
    $fr->[3] !~ /^DBIx::Class|^DBICx::|^DBICTest::/

      or

    grep
      { $_ eq 'DBIC_method_is_indirect_sugar' }
      do { no strict 'refs'; attributes::get( \&{ $fr->[3] }) }
  );


  if (
    defined $fr->[0]
      and
    $check_fr->[0] =~ /^(?:DBIx::Class|DBICx::)/
      and
    $check_fr->[1] !~ /\b(?:CDBICompat|ResultSetProxy)\b/  # no point touching there
  ) {
    DBIx::Class::Exception->throw( sprintf (
      "Illegal internal call of indirect proxy-method %s() with argument '%s': examine the last lines of the proxy method deparse below to determine what to call directly instead at %s on line %d\n\n%s\n\n    Stacktrace starts",
      $fr->[3], $argdesc, @{$fr}[1,2], ( $fr->[6] || do {
        require B::Deparse;
        no strict 'refs';
        B::Deparse->new->coderef2text(\&{$fr->[3]})
      }),
    ), 'with_stacktrace');
  }
}

if (DBIx::Class::_ENV_::ASSERT_NO_ERRONEOUS_METAINSTANCE_USE) {

  no warnings 'redefine';

  my $next_bless = defined(&CORE::GLOBAL::bless)
    ? \&CORE::GLOBAL::bless
    : sub { CORE::bless($_[0], $_[1]) }
  ;

  *CORE::GLOBAL::bless = sub {
    my $class = (@_ > 1) ? $_[1] : CORE::caller();

    # allow for reblessing (role application)
    return $next_bless->( $_[0], $class )
      if defined blessed $_[0];

    my $obj = $next_bless->( $_[0], $class );

    my $calling_sub = (CORE::caller(1))[3] || '';

    (
      # before 5.18 ->isa() will choke on the "0" package
      # which we test for in several obscure cases, sigh...
      !( DBIx::Class::_ENV_::PERL_VERSION < 5.018 )
        or
      $class
    )
      and
    (
      (
        $calling_sub !~ /^ (?:
          DBIx::Class::Schema::clone
            |
          DBIx::Class::DB::setup_schema_instance
        )/x
          and
        $class->isa("DBIx::Class::Schema")
      )
        or
      (
        $calling_sub ne 'DBIx::Class::ResultSource::new'
          and
        $class->isa("DBIx::Class::ResultSource")
      )
    )
      and
    local $Carp::CarpLevel = $Carp::CarpLevel + 1
      and
    Carp::confess("Improper instantiation of '$obj': you *MUST* call the corresponding constructor");


    $obj;
  };
}

1;
