#!/usr/bin/env perl

# Originally by: Zbigniew Lukasiak, C<zz bb yy@gmail.com>
#  but refactored and modified to our nefarious purposes

# XXX I'm not done refactoring this yet --blblack

use strict;
use warnings;

use Pod::Coverage;
use Data::Dumper;
use File::Find::Rule;
use File::Slurp;
use Path::Class;
use Template;

# Convert filename to package name
sub getpac {
    my $file = shift;
    my $filecont = read_file( $file );
    $filecont =~ /package\s*(.*?);/s or return;
    my $pac = $1;
    $pac =~ /\s+(.*)$/;
    return $1;
}

my @files = File::Find::Rule->file()->name('*.pm', '*.pod')->in('lib');

my %docsyms;
for my $file (@files){
    my $package = getpac( $file ) or next;
    my $pc = Pod::Coverage->new(package => $package);
    my %allsyms = map {$_ => 1} $pc->_get_syms($package);
    my $podarr = $pc->_get_pods();
    next if !$podarr;
    for my $sym (@{$podarr}){
        $docsyms{$sym}{$package} = $file if $allsyms{$sym};
    }
}

my @lines;
for my $sym (sort keys %docsyms){
    for my $pac (sort keys %{$docsyms{$sym}}){
        push @lines, {symbol => $sym, package => $pac};
    }
}

my $tt = Template->new({})
|| die Template->error(), "\n";

$tt->process(\*DATA, { lines => \@lines })
|| die $tt->error(), "\n";


__DATA__

=head1 NAME

Method Index

[% FOR line = lines %]
L<[% line.symbol %] ([% line.package %])|[% line.package %]/[% line.symbol %]>
[% END %]
