#!/usr/bin/perl

use strict;
use warnings;
use Class::ISA;

my $class = $ARGV[0];

die "usage: nextalyzer Some::Class" unless $class;

eval "use $class;";

die "Error using $class: $@" if $@;

my @path = reverse Class::ISA::super_path($class);

my %provided;
my %overloaded;

my @warnings;

foreach my $super (@path) {
  my $file = $super;
  $file =~ s/\:\:/\//g;
  $file .= '.pm';
  my $file_path = $INC{$file};
  die "Couldn't get INC for $file, super $super" unless $file_path;
  #warn "$super $file $file_path";
  open IN, '<', $file_path;
  my $in_sub;
  my $ws;
  my $uses_next;
  my @provides;
  my @overloads;
  while (my $line = <IN>) {
    unless ($in_sub) {
      ($ws, $in_sub) = ($line =~ /^(\s*)sub (\S+)/);
      next unless $in_sub;
    }
    if ($line =~ /^$ws\}/) {
      if ($uses_next) {
        push(@overloads, $in_sub);
      } else {
        push(@provides, $in_sub);
      }
      undef $in_sub;
      undef $uses_next;
      undef $ws;
      next;
    }
    $uses_next++ if ($line =~ /\-\>NEXT/);
  }
  close IN;
  foreach (@overloads) {
    push(@warnings, "Method $_ overloaded in $class but not yet provided")
      unless $provided{$_};
    push(@{$overloaded{$_}}, $super);
  }
  $provided{$_} = $super for @provides;
  print "Class $super:\n";
  print "Provides: @provides\n";
  print "Overloads: @overloads\n";
}

print "\n\n";

print join("\n", @warnings);

foreach my $o (keys %overloaded) {
  my $pr = $provided{$o} || "**NEVER**";
  print "Method $o: ".join(' ', reverse @{$overloaded{$o}})." ${pr}\n";
}
