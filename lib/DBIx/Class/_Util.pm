package # hide from PAUSE
  DBIx::Class::_Util;

use warnings;
use strict;

use constant SPURIOUS_VERSION_CHECK_WARNINGS => ($] < 5.010 ? 1 : 0);

BEGIN {
  package # hide from pause
    DBIx::Class::_ENV_;

  use Config;

  use constant {

    # but of course
    BROKEN_FORK => ($^O eq 'MSWin32') ? 1 : 0,

    HAS_ITHREADS => $Config{useithreads} ? 1 : 0,

    # ::Runmode would only be loaded by DBICTest, which in turn implies t/
    DBICTEST => eval { DBICTest::RunMode->is_author } ? 1 : 0,

    # During 5.13 dev cycle HELEMs started to leak on copy
    PEEPEENESS =>
      # request for all tests would force "non-leaky" illusion and vice-versa
      defined $ENV{DBICTEST_ALL_LEAKS}                                              ? !$ENV{DBICTEST_ALL_LEAKS}
      # otherwise confess that this perl is busted ONLY on smokers
    : eval { DBICTest::RunMode->is_smoker } && ($] >= 5.013005 and $] <= 5.013006)  ? 1
      # otherwise we are good
                                                                                    : 0
    ,

    ASSERT_NO_INTERNAL_WANTARRAY => $ENV{DBIC_ASSERT_NO_INTERNAL_WANTARRAY} ? 1 : 0,

    IV_SIZE => $Config{ivsize},

    OS_NAME => $^O,
  };

  if ($] < 5.009_005) {
    require MRO::Compat;
    constant->import( OLD_MRO => 1 );
  }
  else {
    require mro;
    constant->import( OLD_MRO => 0 );
  }
}

use Carp;
use Scalar::Util qw(refaddr weaken);

use base 'Exporter';
our @EXPORT_OK = qw(sigwarn_silencer modver_gt_or_eq fail_on_internal_wantarray refcount);

sub sigwarn_silencer {
  my $pattern = shift;

  croak "Expecting a regexp" if ref $pattern ne 'Regexp';

  my $orig_sig_warn = $SIG{__WARN__} || sub { CORE::warn(@_) };

  return sub { &$orig_sig_warn unless $_[0] =~ $pattern };
}

sub refcount {
  croak "Expecting a reference" if ! length ref $_[0];

  require B;
  # No tempvars - must operate on $_[0], otherwise the pad
  # will count as an extra ref
  B::svref_2object($_[0])->REFCNT;
}

sub modver_gt_or_eq {
  my ($mod, $ver) = @_;

  croak "Nonsensical module name supplied"
    if ! defined $mod or ! length $mod;

  croak "Nonsensical minimum version supplied"
    if ! defined $ver or $ver =~ /[^0-9\.\_]/;

  local $SIG{__WARN__} = sigwarn_silencer( qr/\Qisn't numeric in subroutine entry/ )
    if SPURIOUS_VERSION_CHECK_WARNINGS;

  local $@;
  eval { $mod->VERSION($ver) } ? 1 : 0;
}

{
  my $list_ctx_ok_stack_marker;

  sub fail_on_internal_wantarray {
    return if $list_ctx_ok_stack_marker;

    if (! defined wantarray) {
      croak('fail_on_internal_wantarray() needs a tempvar to save the stack marker guard');
    }

    my $cf = 1;
    while ( ( (caller($cf+1))[3] || '' ) =~ / :: (?:

      # these are public API parts that alter behavior on wantarray
      search | search_related | slice | search_literal

        |

      # these are explicitly prefixed, since we only recognize them as valid
      # escapes when they come from the guts of CDBICompat
      CDBICompat .*? :: (?: search_where | retrieve_from_sql | retrieve_all )

    ) $/x ) {
      $cf++;
    }

    if (
      (caller($cf))[0] =~ /^(?:DBIx::Class|DBICx::)/
    ) {
      my $obj = shift;

      DBIx::Class::Exception->throw( sprintf (
        "Improper use of %s(0x%x) instance in list context at %s line %d\n\n\tStacktrace starts",
        ref($obj), refaddr($obj), (caller($cf))[1,2]
      ), 'with_stacktrace');
    }

    my $mark = [];
    weaken ( $list_ctx_ok_stack_marker = $mark );
    $mark;
  }
}

1;
