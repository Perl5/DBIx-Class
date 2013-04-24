package # hide from PAUSE
  DBIx::Class::_Util;

use warnings;
use strict;

use constant SPURIOUS_VERSION_CHECK_WARNINGS => ($] < 5.010 ? 1 : 0);

use Carp;

use base 'Exporter';
our @EXPORT_OK = qw(modver_gt_or_eq);

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

1;
