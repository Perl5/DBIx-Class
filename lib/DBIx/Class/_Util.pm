package # hide from PAUSE
  DBIx::Class::_Util;

use warnings;
use strict;

use constant SPURIOUS_VERSION_CHECK_WARNINGS => ($] < 5.010 ? 1 : 0);

use Carp;
use Scalar::Util qw(refaddr weaken);

use base 'Exporter';
our @EXPORT_OK = qw(modver_gt_or_eq fail_on_internal_wantarray);

sub modver_gt_or_eq {
  my ($mod, $ver) = @_;

  croak "Nonsensical module name supplied"
    if ! defined $mod or ! length $mod;

  croak "Nonsensical minimum version supplied"
    if ! defined $ver or $ver =~ /[^0-9\.\_]/;

  local $SIG{__WARN__} = do {
    my $orig_sig_warn = $SIG{__WARN__} || sub { warn @_ };
    sub {
      $orig_sig_warn->(@_) unless $_[0] =~ /\Qisn't numeric in subroutine entry/
    }
  } if SPURIOUS_VERSION_CHECK_WARNINGS;

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
