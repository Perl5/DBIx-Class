package DBICTest::Util;

use warnings;
use strict;

use Config;
use Carp 'confess';
use Scalar::Util 'blessed';

use base 'Exporter';
our @EXPORT_OK = qw(local_umask stacktrace check_customcond_args);

sub local_umask {
  return unless defined $Config{d_umask};

  die 'Calling local_umask() in void context makes no sense'
    if ! defined wantarray;

  my $old_umask = umask(shift());
  die "Setting umask failed: $!" unless defined $old_umask;

  return bless \$old_umask, 'DBICTest::Util::UmaskGuard';
}
{
  package DBICTest::Util::UmaskGuard;
  sub DESTROY {
    local ($@, $!);
    eval { defined (umask ${$_[0]}) or die };
    warn ( "Unable to reset old umask ${$_[0]}: " . ($!||'Unknown error') )
      if ($@ || $!);
  }
}

sub stacktrace {
  my $frame = shift;
  $frame++;
  my (@stack, @frame);

  while (@frame = caller($frame++)) {
    push @stack, [@frame[3,1,2]];
  }

  return undef unless @stack;

  $stack[0][0] = '';
  return join "\tinvoked as ", map { sprintf ("%s at %s line %d\n", @$_ ) } @stack;
}

sub check_customcond_args ($) {
  my $args = shift;

  confess "Expecting a hashref"
    unless ref $args eq 'HASH';

  for (qw(foreign_relname self_alias foreign_alias)) {
    confess "Custom condition argument '$_' must be a plain string"
      if length ref $args->{$_} or ! length $args->{$_};
  }

  confess "Custom condition argument 'self_resultsource' must be a rsrc instance"
    unless defined blessed $args->{self_resultsource} and $args->{self_resultsource}->isa('DBIx::Class::ResultSource');

  confess "Passed resultsource has no record of the supplied rel_name - likely wrong \$rsrc"
    unless ref $args->{self_resultsource}->relationship_info($args->{foreign_relname});

  if (defined $args->{self_rowobj}) {
    confess "Custom condition argument 'self_rowobj' must be a result instance"
      unless defined blessed $args->{self_rowobj} and $args->{self_rowobj}->isa('DBIx::Class::Row');
  }

  $args;
}

1;
