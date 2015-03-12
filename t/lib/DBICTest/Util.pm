package DBICTest::Util;

use warnings;
use strict;

# this noop trick initializes the STDOUT, so that the TAP::Harness
# issued IO::Select->can_read calls (which are blocking wtf wtf wtf)
# keep spinning and scheduling jobs
# This results in an overall much smoother job-queue drainage, since
# the Harness blocks less
# (ideally this needs to be addressed in T::H, but a quick patchjob
# broke everything so tabling it for now)
BEGIN {
  if ($INC{'Test/Builder.pm'}) {
    local $| = 1;
    print "#\n";
  }
}

use Module::Runtime 'module_notional_filename';
BEGIN {
  for my $mod (qw( SQL::Abstract::Test SQL::Abstract )) {
    if ( $INC{ module_notional_filename($mod) } ) {
      # FIXME this does not seem to work in BEGIN - why?!
      #require Carp;
      #$Carp::Internal{ (__PACKAGE__) }++;
      #Carp::croak( __PACKAGE__ . " must be loaded before $mod" );

      my ($fr, @frame) = 1;
      while (@frame = caller($fr++)) {
        last if $frame[1] !~ m|^t/lib/DBICTest|;
      }

      die __PACKAGE__ . " must be loaded before $mod (or modules using $mod) at $frame[1] line $frame[2]\n";
    }
  }
}

use Config;
use Carp 'confess';
use Scalar::Util qw(blessed refaddr);
use DBIx::Class::_Util;

use base 'Exporter';
our @EXPORT_OK = qw(local_umask stacktrace check_customcond_args visit_namespaces);

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
    &DBIx::Class::_Util::detected_reinvoked_destructor;

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

  my $struct_cnt = 0;

  if (defined $args->{self_result_object} or defined $args->{self_rowobj} ) {
    $struct_cnt++;
    for (qw(self_result_object self_rowobj)) {
      confess "Custom condition argument '$_' must be a result instance"
        unless defined blessed $args->{$_} and $args->{$_}->isa('DBIx::Class::Row');
    }

    confess "Current and legacy self_result_object arguments do not match"
      if refaddr($args->{self_result_object}) != refaddr($args->{self_rowobj});
  }

  if (defined $args->{foreign_values}) {
    $struct_cnt++;

    confess "Custom condition argument 'foreign_values' must be a hash reference"
      unless ref $args->{foreign_values} eq 'HASH';
  }

  confess "Data structures supplied on both ends of a relationship"
    if $struct_cnt == 2;

  $args;
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

  return $visited_count;
}

1;
