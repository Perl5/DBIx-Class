package DBIx::Class::StartupCheck;

# Temporary - tempextlib
use warnings;
use strict;
use namespace::clean;
BEGIN {
  # There can be only one of these, make sure we get the bundled part and
  # *not* something off the site lib
  for (qw(
    Sub::Quote
  )) {
    (my $incfn = "$_.pm") =~ s|::|/|g;

    if ($INC{$incfn}) {
      die "\n\t*TEMPORARY* TRIAL RELEASE REQUIREMENTS VIOLATED\n\n"
        . "Unable to continue - a part of the bundled templib contents "
        . "was already loaded (likely an older version from CPAN). "
        . "Make sure that @{[ __PACKAGE__ ]} is loaded before $_\n"
        . "\n\tThis *WILL NOT* be necessary for the official DBIC release\n\n"
      ;
    }
  }

  require File::Spec;
  our ($HERE) = File::Spec->rel2abs(
    File::Spec->catdir( (File::Spec->splitpath(__FILE__))[1], '_TempExtlib' )
  ) =~ /^(.*)$/; # screw you, taint mode

  die "TempExtlib $HERE does not seem to exist - perhaps you need to run `perl Makefile.PL` in the DBIC checkout?\n"
    unless -d $HERE;

  unshift @INC, $HERE;
}

1;

__END__

=head1 NAME

DBIx::Class::StartupCheck - Run environment checks on startup

=head1 SYNOPSIS

  use DBIx::Class::StartupCheck;

=head1 DESCRIPTION

This module used to check for, and if necessary issue a warning for, a
particular bug found on Red Hat and Fedora systems using their system
perl build. As of September 2008 there are fixed versions of perl for
all current Red Hat and Fedora distributions, but the old check still
triggers, incorrectly flagging those versions of perl to be buggy. A
more comprehensive check has been moved into the test suite in
C<t/99rh_perl_perf_bug.t> and further information about the bug has been
put in L<DBIx::Class::Manual::Troubleshooting>.

Other checks may be added from time to time.

Any checks herein can be disabled by setting an appropriate environment
variable. If your system suffers from a particular bug, you will get a
warning message on startup sent to STDERR, explaining what to do about
it and how to suppress the message. If you don't see any messages, you
have nothing to worry about.

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.
