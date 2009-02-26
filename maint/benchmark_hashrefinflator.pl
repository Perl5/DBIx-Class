#!/usr/bin/perl

#
# So you wrote a new mk_hash implementation which passed all tests (particularly 
# t/68inflate_resultclass_hashrefinflator) and would like to see how it holds up 
# against older versions of the same. Just add your coderef to the HRI::Bench 
# namespace and add a name/ref pair to the %bench_list hash. Happy testing.

package DBIx::Class::ResultClass::HashRefInflator::Bench;

use warnings;
use strict;

my $current_mk_hash;
$current_mk_hash = sub {
    if (ref $_[0] eq 'ARRAY') {     # multi relationship 
        return [ map { $current_mk_hash->(@$_) || () } (@_) ];
    }
    else {
        my $hash = {
            # the main hash could be an undef if we are processing a skipped-over join 
            $_[0] ? %{$_[0]} : (),

            # the second arg is a hash of arrays for each prefetched relation 
            map
                { $_ => $current_mk_hash->( @{$_[1]->{$_}} ) }
                ( $_[1] ? (keys %{$_[1]}) : () )
        };

        # if there is at least one defined column consider the resultset real 
        # (and not an emtpy has_many rel containing one empty hashref) 
        for (values %$hash) {
            return $hash if defined $_;
        }

        return undef;
    }
};

# the (incomplete, fails a test) implementation before svn:4760
my $old_mk_hash;
$old_mk_hash = sub {
    my ($me, $rest) = @_;

    # $me is the hashref of cols/data from the immediate resultsource
    # $rest is a deep hashref of all the data from the prefetched
    # related sources.

    # to avoid emtpy has_many rels contain one empty hashref
    return undef if (not keys %$me);

    my $def;

    foreach (values %$me) {
        if (defined $_) {
            $def = 1;
            last;
        }
    }
    return undef unless $def;

    return { %$me,
        map {
          ( $_ =>
             ref($rest->{$_}[0]) eq 'ARRAY'
                 ? [ grep defined, map $old_mk_hash->(@$_), @{$rest->{$_}} ]
                 : $old_mk_hash->( @{$rest->{$_}} )
          )
        } keys %$rest
    };
};


our %bench_list = (
    current_implementation => $current_mk_hash,
    old_implementation => $old_mk_hash,
);

1;

package benchmark_hashrefinflator;

use warnings;
use strict;

use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/../t/lib");

use Benchmark qw/timethis cmpthese/;
use DBICTest;

chdir ("$FindBin::Bin/..");
my $schema = DBICTest->init_schema();

my $test_sub = sub {
    my $rs_hashrefinf = $schema->resultset ('Artist')->search ({}, {
        prefetch => { cds => 'tracks' },
    });
    $rs_hashrefinf->result_class('DBIx::Class::ResultClass::HashRefInflator::Bench');
    my @stuff = $rs_hashrefinf->all;
};


my $results;
for my $b (keys %DBIx::Class::ResultClass::HashRefInflator::Bench::bench_list) {

    print "Timing $b... ";

    # switch the inflator
    no warnings qw/redefine once/;
    no strict qw/refs/;
    local *DBIx::Class::ResultClass::HashRefInflator::Bench::inflate_result = sub {
        return $DBIx::Class::ResultClass::HashRefInflator::Bench::bench_list{$b}->(@_[2,3]);
    };

    $results->{$b} = timethis (-2, $test_sub);
}
cmpthese ($results);
