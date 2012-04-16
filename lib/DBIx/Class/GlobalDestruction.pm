# This is just a concept-test. If works as intended will ship in its own
# right as Devel::GlobalDestruction::PP or perhaps even as part of rafls
# D::GD itself

package # hide from pause
  DBIx::Class::GlobalDestruction;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = 'in_global_destruction';

use DBIx::Class::Exception;

if (defined ${^GLOBAL_PHASE}) {
  eval 'sub in_global_destruction () { ${^GLOBAL_PHASE} eq q[DESTRUCT] }';
}
elsif (eval { require Devel::GlobalDestruction }) { # use the XS version if available
  *in_global_destruction = \&Devel::GlobalDestruction::in_global_destruction;
}
else {
  my ($in_global_destruction, $before_is_installed);

  eval <<'PP_IGD';

sub in_global_destruction () { $in_global_destruction }

END {
  # SpeedyCGI runs END blocks every cycle but keeps object instances
  # hence we have to disable the globaldestroy hatch, and rely on the
  # eval traps (which appears to work, but are risky done so late)
  $in_global_destruction = 1 unless $CGI::SpeedyCGI::i_am_speedy;
}

# threads do not execute the global ENDs (it would be stupid). However
# one can register a new END via simple string eval within a thread, and
# achieve the same result. A logical place to do this would be CLONE, which
# is claimed to run in the context of the new thread. However this does
# not really seem to be the case - any END evaled in a CLONE is ignored :(
# Hence blatantly hooking threads::create
if ($INC{'threads.pm'}) {
  require Class::Method::Modifiers;
  Class::Method::Modifiers::install_modifier( threads => before => create => sub {
    my $orig_target_cref = $_[1];
    $_[1] = sub {
      { local $@; eval 'END { $in_global_destruction = 1 }' }
      $orig_target_cref->();
    };
  });
  $before_is_installed = 1;
}

# just in case threads got loaded after DBIC (silly)
sub CLONE {
  DBIx::Class::Exception->throw("You must load the 'threads' module before @{[ __PACKAGE__ ]}")
    unless $before_is_installed;
}

PP_IGD

}

1;
