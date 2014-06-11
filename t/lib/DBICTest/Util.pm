package DBICTest::Util;

use warnings;
use strict;

use Config;
use Carp 'confess';
use Scalar::Util qw(blessed refaddr);

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

  for (qw(rel_name foreign_relname self_alias foreign_alias)) {
    confess "Custom condition argument '$_' must be a plain string"
      if length ref $args->{$_} or ! length $args->{$_};
  }

  confess "Current and legacy rel_name arguments do not match"
    if $args->{rel_name} ne $args->{foreign_relname};

  confess "Custom condition argument 'self_resultsource' must be a rsrc instance"
    unless defined blessed $args->{self_resultsource} and $args->{self_resultsource}->isa('DBIx::Class::ResultSource');

  confess "Passed resultsource has no record of the supplied rel_name - likely wrong \$rsrc"
    unless ref $args->{self_resultsource}->relationship_info($args->{rel_name});

  my $rowobj_cnt = 0;

  if (defined $args->{self_resultobj} or defined $args->{self_rowobj} ) {
    $rowobj_cnt++;
    for (qw(self_resultobj self_rowobj)) {
      confess "Custom condition argument '$_' must be a result instance"
        unless defined blessed $args->{$_} and $args->{$_}->isa('DBIx::Class::Row');
    }

    confess "Current and legacy self_resultobj arguments do not match"
      if refaddr($args->{self_resultobj}) != refaddr($args->{self_rowobj});
  }

  if (defined $args->{foreign_resultobj}) {
    $rowobj_cnt++;

    confess "Custom condition argument 'foreign_resultobj' must be a result instance"
      unless defined blessed $args->{foreign_resultobj} and $args->{foreign_resultobj}->isa('DBIx::Class::Row');
  }

  confess "Result objects supplied on both ends of a relationship"
    if $rowobj_cnt == 2;

  $args;
}

1;
