package DBIx::Class::ResultClass::HashRefInflator;

use strict;
use warnings;

our %inflator_cache;
our $inflate_data;

=head1 NAME

DBIx::Class::ResultClass::HashRefInflator

=head1 SYNOPSIS

 my $rs = $schema->resultset('CD');

 $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');

=head1 DESCRIPTION

DBIx::Class is not built for speed: it's built for convenience and
ease of use. But sometimes you just need to get the data, and skip the
fancy objects. That is what this class provides.

There are two ways of using this class.

=over

=item *

Specify C<< $rs->result_class >> on a specific resultset to affect only that
resultset (and any chained off of it); or

=item *

Specify C<< __PACKAGE__->result_class >> on your source object to force all
uses of that result source to be inflated to hash-refs - this approach is not
recommended.

=back

=head1 AUTOMATICALLY INFLATING COLUMN VALUES

So you want to skip the DBIx::Class object creation part, but you still want 
all your data to be inflated according to the rules you defined in your table
classes. Setting the global variable 
C<$DBIx::Class::ResultClass::HashRefInflator::inflate_data> to a true value
will instruct L<mk_hash> to interrogate the processed columns and apply any
inflation methods declared via L<DBIx::Class::InflateColumn/inflate_column>.

For increased speed the inflation method lookups are cached in 
C<%DBIx::Class::ResultClass::HashRefInflator::inflator_cache>. Make sure to 
reset this hash if you modify column inflators at run time.

=head1 METHODS

=head2 inflate_result

Inflates the result and prefetched data into a hash-ref using L<mk_hash>.

=cut

sub inflate_result {
    my ($self, $source, $me, $prefetch) = @_;

    my $hashref = mk_hash($me, $prefetch);
    inflate_hash ($source->schema, $source->result_class, $hashref) if $inflate_data;
    return $hashref;
}

=head2 mk_hash

This does all the work of inflating the (pre)fetched data.

=cut

##############
# NOTE
#
# Generally people use this to gain as much speed as possible. If a new mk_hash is
# implemented, it should be benchmarked using the maint/benchmark_hashrefinflator.pl
# script (in addition to passing all tests of course :). Additional instructions are 
# provided in the script itself.
#

sub mk_hash { 
    if (ref $_[0] eq 'ARRAY') {     # multi relationship
        return [ map { mk_hash (@$_) || () } (@_) ];
    }
    else {
        my $hash = {
            # the main hash could be an undef if we are processing a skipped-over join
            $_[0] ? %{$_[0]} : (),

            # the second arg is a hash of arrays for each prefetched relation
            map
                { $_ => mk_hash( @{$_[1]->{$_}} ) }
                ( $_[1] ? (keys %{$_[1]}) : () )
        };

        # if there is at least one defined column consider the resultset real
        # (and not an emtpy has_many rel containing one empty hashref)
        for (values %$hash) {
            return $hash if defined $_;
        }

        return undef;
    }
}

=head2 inflate_hash

This walks through a hashref produced by L<mk_hash> and inflates any data 
for which there is a registered inflator in the C<column_info>

=cut

sub inflate_hash {
    my ($schema, $rc, $data) = @_;

    foreach my $column (keys %{$data}) {

        if (ref $data->{$column} eq 'HASH') {
            inflate_hash ($schema, $schema->source ($rc)->related_class ($column), $data->{$column});
        } 
        elsif (ref $data->{$column} eq 'ARRAY') {
            foreach my $rel (@{$data->{$column}}) {
                inflate_hash ($schema, $schema->source ($rc)->related_class ($column), $rel);
            }
        }
        else {
            # "null is null is null"
            next if not defined $data->{$column};

            # cache the inflator coderef
            unless (exists $inflator_cache{$rc}{$column}) {
                $inflator_cache{$rc}{$column} = exists $schema->source ($rc)->_relationships->{$column}
                    ? undef     # currently no way to inflate a column sharing a name with a rel 
                    : $rc->column_info($column)->{_inflate_info}{inflate}
                ;
            }

            if ($inflator_cache{$rc}{$column}) {
                $data->{$column} = $inflator_cache{$rc}{$column}->($data->{$column});
            }
        }
    }
}

=head1 CAVEAT

This will not work for relationships that have been prefetched. Consider the
following:

 my $artist = $artitsts_rs->search({}, {prefetch => 'cds' })->first;

 my $cds = $artist->cds;
 $cds->result_class('DBIx::Class::ResultClass::HashRefInflator');
 my $first = $cds->first; 

C<$first> will B<not> be a hashref, it will be a normal CD row since 
HashRefInflator only affects resultsets at inflation time, and prefetch causes
relations to be inflated when the master C<$artist> row is inflated.

=cut

1;
