#!/usr/bin/perl -wT

use strict;
use Test::More tests => 843;
use_ok('Data::Page');

my $name;

foreach my $line (<DATA>) {
    chomp $line;
    next unless $line;

    if ( $line =~ /^# ?(.+)/ ) {
        $name = $1;
        next;
    }

    print "Line is: $line\n";
    my @vals = map { /^undef$/ ? undef : /^''$/ ? '' : $_ } split /\s+/,
        $line;

    my $page = Data::Page->new( @vals[ 0, 1, 2 ] );
    print "Old style\n";
    check( $page, $name, @vals );

    $page = Data::Page->new();
    $page->total_entries( $vals[0] );
    $page->entries_per_page( $vals[1] );
    $page->current_page( $vals[2] );
    print "New style\n";
    check( $page, $name, @vals );
}

my $page = Data::Page->new( 0, 10 );
isa_ok( $page, 'Data::Page' );
my @empty;
my @spliced = $page->splice( \@empty );
is( scalar(@spliced), 0, "Splice on empty is empty" );

sub check {
    my ( $page, $name, @vals ) = @_;
    isa_ok( $page, 'Data::Page' );

    is( $page->first_page,    $vals[3], "$name: first page" );
    is( $page->last_page,     $vals[4], "$name: last page" );
    is( $page->first,         $vals[5], "$name: first" );
    is( $page->last,          $vals[6], "$name: last" );
    is( $page->previous_page, $vals[7], "$name: previous_page" );
    is( $page->current_page,  $vals[8], "$name: current_page" );
    is( $page->next_page,     $vals[9], "$name: next_page" );

    my @integers = ( 0 .. $vals[0] - 1 );
    @integers = $page->splice( \@integers );
    my $integers = join ',', @integers;
    is( $integers, $vals[10], "$name: splice" );
    is( $page->entries_on_this_page, $vals[11],
        "$name: entries_on_this_page" );

    my $skipped = $vals[5] - 1;
    $skipped = 0 if $skipped < 0;
    is( $page->skipped, $skipped, "$name: skipped" );
    $page->change_entries_per_page( $vals[12] );
    is( $page->current_page, $vals[13], "$name: change_entries_per_page" );
}

# Format of test data: 0=number of entries, 1=entries per page, 2=current page,
# 3=first page, 4=last page, 5=first entry on page, 6=last entry on page,
# 7=previous page, 8=current page, 9=next page, 10=current entries,
# 11=current number of entries, 12=new entries per page, 13=new page

__DATA__
# Initial test
50 10 1    1 5 1 10 undef 1 2 0,1,2,3,4,5,6,7,8,9            10    15 1
50 10 2    1 5 11 20 1 2 3 10,11,12,13,14,15,16,17,18,19     10    15 1
50 10 3    1 5 21 30 2 3 4 20,21,22,23,24,25,26,27,28,29     10    15 2
50 10 4    1 5 31 40 3 4 5 30,31,32,33,34,35,36,37,38,39     10    15 3
50 10 5    1 5 41 50 4 5 undef 40,41,42,43,44,45,46,47,48,49 10    15 3

# Under 10
1 10 1    1 1 1 1 undef 1 undef 0                     1    15 1
2 10 1    1 1 1 2 undef 1 undef 0,1                   2    15 1
3 10 1    1 1 1 3 undef 1 undef 0,1,2                 3    15 1
4 10 1    1 1 1 4 undef 1 undef 0,1,2,3               4    15 1
5 10 1    1 1 1 5 undef 1 undef 0,1,2,3,4             5    15 1
6 10 1    1 1 1 6 undef 1 undef 0,1,2,3,4,5           6    15 1
7 10 1    1 1 1 7 undef 1 undef 0,1,2,3,4,5,6         7    15 1
8 10 1    1 1 1 8 undef 1 undef 0,1,2,3,4,5,6,7       8    15 1
9 10 1    1 1 1 9 undef 1 undef 0,1,2,3,4,5,6,7,8     9    15 1
10 10 1   1 1 1 10 undef 1 undef 0,1,2,3,4,5,6,7,8,9  10   15 1

# Over 10
11 10 1    1 2 1 10 undef 1 2 0,1,2,3,4,5,6,7,8,9     10   10 1
11 10 2    1 2 11 11 1 2 undef 10                     1    10 2
12 10 1    1 2 1 10 undef 1 2 0,1,2,3,4,5,6,7,8,9     10   10 1
12 10 2    1 2 11 12 1 2 undef 10,11                  2    10 2
13 10 1    1 2 1 10 undef 1 2 0,1,2,3,4,5,6,7,8,9     10   10 1
13 10 2    1 2 11 13 1 2 undef 10,11,12               3    10 2

# Under 20
19 10 1    1 2 1 10 undef 1 2 0,1,2,3,4,5,6,7,8,9            10   4 1
19 10 2    1 2 11 19 1 2 undef 10,11,12,13,14,15,16,17,18    9    4 3
20 10 1    1 2 1 10 undef 1 2 0,1,2,3,4,5,6,7,8,9            10   4 1
20 10 2    1 2 11 20 1 2 undef 10,11,12,13,14,15,16,17,18,19 10   4 3

# Over 20
21 10 1    1 3 1 10 undef 1 2 0,1,2,3,4,5,6,7,8,9        10   19 1
21 10 2    1 3 11 20 1 2 3 10,11,12,13,14,15,16,17,18,19 10   19 1
21 10 3    1 3 21 21 2 3 undef 20                        1    19 2
22 10 1    1 3 1 10 undef 1 2 0,1,2,3,4,5,6,7,8,9        10   19 1
22 10 2    1 3 11 20 1 2 3 10,11,12,13,14,15,16,17,18,19 10   19 1
22 10 3    1 3 21 22 2 3 undef 20,21                     2    19 2
23 10 1    1 3 1 10 undef 1 2 0,1,2,3,4,5,6,7,8,9        10   19 1
23 10 2    1 3 11 20 1 2 3 10,11,12,13,14,15,16,17,18,19 10   19 1
23 10 3    1 3 21 23 2 3 undef 20,21,22                  3    19 2

# Zero test
0 10 1    1 1 0 0 undef 1 undef '' 0    5 1
