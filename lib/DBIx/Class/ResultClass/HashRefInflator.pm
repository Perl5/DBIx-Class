package DBIx::Class::ResultClass::HashRefInflator;

use strict;
use warnings;

=head1 NAME

DBIx::Class::ResultClass::HashRefInflator

=head1 SYNOPSIS

 use DBIx::Class::ResultClass::HashRefInflator;

 my $rs = $schema->resultset('CD');

 $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    or
 $rs->result_class(DBIx::Class::ResultClass::HashRefInflator->new (%args));

 while (my $hashref = $rs->next) {
    ...
 }

=head1 DESCRIPTION

DBIx::Class is faster than older ORMs like Class::DBI but it still isn't 
designed primarily for speed. Sometimes you need to quickly retrieve the data
from a massive resultset, while skipping the creation of fancy row objects.
Specifying this class as a C<result_class> for a resultset will change C<< $rs->next >>
to return a plain data hash-ref (or a list of such hash-refs if C<< $rs->all >> is used).

There are two ways of using this class:

=over

=item *

Supply an instance of DBIx::Class::ResultClass::HashRefInflator to
C<< $rs->result_class >>. See L</ARGUMENTS> for a list of valid
arguments to new().

=item *

Another way is to simply supply the class name as a string to
C<< $rs->result_class >>. Equivalent to passing
DBIx::Class::ResultClass::HashRefInflator->new().

=back

There are two ways of applying this class to a resultset:

=over

=item *

Specify C<< $rs->result_class >> on a specific resultset to affect only that
resultset (and any chained off of it); or

=item *

Specify C<< __PACKAGE__->result_class >> on your source object to force all
uses of that result source to be inflated to hash-refs - this approach is not
recommended.

=back

=cut

##############
# NOTE
#
# Generally people use this to gain as much speed as possible. If a new &mk_hash is
# implemented, it should be benchmarked using the maint/benchmark_hashrefinflator.pl
# script (in addition to passing all tests of course :). Additional instructions are
# provided in the script itself.
#

# This coderef is a simple recursive function
# Arguments: ($me, $prefetch) from inflate_result() below
my $mk_hash;
$mk_hash = sub {
    if (ref $_[0] eq 'ARRAY') {     # multi relationship
        return [ map { $mk_hash->(@$_) || () } (@_) ];
    }
    else {
        my $hash = {
            # the main hash could be an undef if we are processing a skipped-over join
            $_[0] ? %{$_[0]} : (),

            # the second arg is a hash of arrays for each prefetched relation
            map
                { $_ => $mk_hash->( @{$_[1]->{$_}} ) }
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

# This is the inflator
my $inflate_hash;
$inflate_hash = sub {
    my ($hri_instance, $schema, $rc, $data) = @_;

    foreach my $column (keys %{$data}) {

        if (ref $data->{$column} eq 'HASH') {
            $inflate_hash->($hri_instance, $schema, $schema->source ($rc)->related_class ($column), $data->{$column});
        } 
        elsif (ref $data->{$column} eq 'ARRAY') {
            foreach my $rel (@{$data->{$column}}) {
                $inflate_hash->($hri_instance, $schema, $schema->source ($rc)->related_class ($column), $rel);
            }
        }
        else {
            # "null is null is null"
            next if not defined $data->{$column};

            # cache the inflator coderef
            unless (exists $hri_instance->{_inflator_cache}{$rc}{$column}) {
                $hri_instance->{_inflator_cache}{$rc}{$column} = exists $schema->source ($rc)->_relationships->{$column}
                    ? undef     # currently no way to inflate a column sharing a name with a rel 
                    : $rc->column_info($column)->{_inflate_info}{inflate}
                ;
            }

            if ($hri_instance->{_inflator_cache}{$rc}{$column}) {
                $data->{$column} = $hri_instance->{_inflator_cache}{$rc}{$column}->($data->{$column});
            }
        }
    }
};


=head1 METHODS

=head2 new

 $class->new( %args );
 $class->new({ %args });

Creates a new DBIx::Class::ResultClass::HashRefInflator object. Takes the following
arguments:

=over

=item inflate_columns

Sometimes you still want all your data to be inflated to the corresponding 
objects according to the rules you defined in your table classes (e.g. you
want all dates in the resulting hash to be replaced with the equivalent 
DateTime objects). Supplying C<< inflate_columns => 1 >> to the constructor will
interrogate the processed columns and apply any inflation methods declared 
via L<DBIx::Class::InflateColumn/inflate_column> to the contents of the 
resulting hash-ref.

=back

=cut

sub new {
    my $self = shift;
    my $args = { (ref $_[0] eq 'HASH') ? %{$_[0]} : @_ };
    return bless ($args, $self)
}

=head2 inflate_result

Inflates the result and prefetched data into a hash-ref (invoked by L<DBIx::Class::ResultSet>)

=cut


sub inflate_result {
    my ($self, $source, $me, $prefetch) = @_;

    my $hashref = $mk_hash->($me, $prefetch);

    # if $self is an instance and inflate_columns is set
    if ( (ref $self) and $self->{inflate_columns} ) {
        $inflate_hash->($self, $source->schema, $source->result_class, $hashref);
    }

    return $hashref;
}


=head1 CAVEATS

=over

=item *

This will not work for relationships that have been prefetched. Consider the
following:

 my $artist = $artitsts_rs->search({}, {prefetch => 'cds' })->first;

 my $cds = $artist->cds;
 $cds->result_class('DBIx::Class::ResultClass::HashRefInflator');
 my $first = $cds->first; 

C<$first> will B<not> be a hashref, it will be a normal CD row since 
HashRefInflator only affects resultsets at inflation time, and prefetch causes
relations to be inflated when the master C<$artist> row is inflated.

=item *

When using C<inflate_columns>, the inflation method lookups are cached in the
HashRefInflator object for additional speed. If you modify column inflators at run
time, make sure to grab a new instance of this class to avoid cached surprises.

=back

=cut

1;
