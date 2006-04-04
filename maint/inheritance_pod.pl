#!/usr/bin/perl
use strict;
use warnings;
use lib qw(lib t/lib);

# USAGE:
# maint/inheritance_pod.pl Some::Module

my $module = $ARGV[0];
eval(" require $module; ");

my @modules = Class::C3::calculateMRO($module);
shift( @modules );

print "=head1 INHERITED METHODS\n\n";

foreach my $module (@modules) {
    print "=head2 $module\n\n";
    print "=over 4\n\n";
    my $file = $module;
    $file =~ s/::/\//g;
    $file .= '.pm';
    foreach my $path (@INC){
        if (-e "$path/$file") {
            open(MODULE,"<$path/$file");
            while (my $line = <MODULE>) {
                if ($line=~/^\s*sub ([a-z][a-z_]+) \{/) {
                    my $method = $1;
                    print "=item *\n\n";
                    print "L<$method|$module/$method>\n\n";
                }
            }
            close(MODULE);
            last;
        }
    }
    print "=back\n\n";
}

1;
