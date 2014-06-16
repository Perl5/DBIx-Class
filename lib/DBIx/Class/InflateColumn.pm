package DBIx::Class::InflateColumn;

use strict;
use warnings;

use base qw/DBIx::Class::Row/;

=head1 NAME

DBIx::Class::InflateColumn - Automatically create references from column data

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->inflate_column('column_name', {
    inflate => sub {
      my ($raw_value_from_db, $result_object) = @_;
      ...
    },
    deflate => sub {
      my ($inflated_value_from_user, $result_object) = @_;
      ...
    },
  });

=head1 DESCRIPTION

This component translates column data into references, i.e. "inflating"
the column data. It also "deflates" references into an appropriate format
for the database.

It can be used, for example, to automatically convert to and from
L<DateTime> objects for your date and time fields. There's a
convenience component to actually do that though, try
L<DBIx::Class::InflateColumn::DateTime>.

It will handle all types of references except scalar references. It
will not handle scalar values, these are ignored and thus passed
through to L<SQL::Abstract>. This is to allow setting raw values to
"just work". Scalar references are passed through to the database to
deal with, to allow such settings as C< \'year + 1'> and C< \'DEFAULT' >
to work.

If you want to filter plain scalar values and replace them with
something else, see L<DBIx::Class::FilterColumn>.

=head1 METHODS

=head2 inflate_column

Instruct L<DBIx::Class> to inflate the given column.

In addition to the column name, you must provide C<inflate> and
C<deflate> methods. The C<inflate> method is called when you access
the field, while the C<deflate> method is called when the field needs
to used by the database.

For example, if you have a table C<events> with a timestamp field
named C<insert_time>, you could inflate the column in the
corresponding table class using something like:

    __PACKAGE__->inflate_column('insert_time', {
        inflate => sub {
          my ($insert_time_raw_value, $event_result_object) = @_;
          DateTime->from_epoch( epoch => $insert_time_raw_value );
        },
        deflate => sub {
          my ($insert_time_dt_object, $event_result_object) = @_;
          $insert_time_dt_object->epoch;
        },
    });

The coderefs you set for inflate and deflate are called with two parameters,
the first is the value of the column to be inflated/deflated, the second is
the result object itself.

In this example, calls to an event's C<insert_time> accessor return a
L<DateTime> object. This L<DateTime> object is later "deflated" back
to the integer epoch representation when used in the database layer.
For a much more thorough handling of the above example, please see
L<DBIx::Class::DateTime::Epoch>

=cut

sub inflate_column {
  my ($self, $col, $attrs) = @_;

  my $colinfo = $self->column_info($col);

  $self->throw_exception("InflateColumn does not work with FilterColumn")
    if $self->isa('DBIx::Class::FilterColumn') &&
      defined $colinfo->{_filter_info};

  $self->throw_exception("No such column $col to inflate")
    unless $self->has_column($col);
  $self->throw_exception("inflate_column needs attr hashref")
    unless ref $attrs eq 'HASH';
  $colinfo->{_inflate_info} = $attrs;
  my $acc = $colinfo->{accessor};
  $self->mk_group_accessors('inflated_column' => [ (defined $acc ? $acc : $col), $col]);
  return 1;
}

sub _inflated_column {
  my ($self, $col, $value) = @_;
  return $value unless defined $value; # NULL is NULL is NULL
  my $info = $self->column_info($col)
    or $self->throw_exception("No column info for $col");
  return $value unless exists $info->{_inflate_info};
  my $inflate = $info->{_inflate_info}{inflate};
  $self->throw_exception("No inflator for $col") unless defined $inflate;
  return $inflate->($value, $self);
}

sub _deflated_column {
  my ($self, $col, $value) = @_;
#  return $value unless ref $value && blessed($value); # If it's not an object, don't touch it
  ## Leave scalar refs (ala SQL::Abstract literal SQL), untouched, deflate all other refs
  return $value unless (ref $value && ref($value) ne 'SCALAR');
  my $info = $self->column_info($col) or
    $self->throw_exception("No column info for $col");
  return $value unless exists $info->{_inflate_info};
  my $deflate = $info->{_inflate_info}{deflate};
  $self->throw_exception("No deflator for $col") unless defined $deflate;
  return $deflate->($value, $self);
}

=head2 get_inflated_column

  my $val = $obj->get_inflated_column($col);

Fetch a column value in its inflated state.  This is directly
analogous to L<DBIx::Class::Row/get_column> in that it only fetches a
column already retrieved from the database, and then inflates it.
Throws an exception if the column requested is not an inflated column.

=cut

sub get_inflated_column {
  my ($self, $col) = @_;
  $self->throw_exception("$col is not an inflated column")
    unless exists $self->column_info($col)->{_inflate_info};
  return $self->{_inflated_column}{$col}
    if exists $self->{_inflated_column}{$col};

  my $val = $self->get_column($col);
  return $val if ref $val eq 'SCALAR';  #that would be a not-yet-reloaded sclarref update

  return $self->{_inflated_column}{$col} = $self->_inflated_column($col, $val);
}

=head2 set_inflated_column

  my $copy = $obj->set_inflated_column($col => $val);

Sets a column value from an inflated value.  This is directly
analogous to L<DBIx::Class::Row/set_column>.

=cut

sub set_inflated_column {
  my ($self, $col, $inflated) = @_;
  $self->set_column($col, $self->_deflated_column($col, $inflated));
#  if (blessed $inflated) {
  if (ref $inflated && ref($inflated) ne 'SCALAR') {
    $self->{_inflated_column}{$col} = $inflated;
  } else {
    delete $self->{_inflated_column}{$col};
  }
  return $inflated;
}

=head2 store_inflated_column

  my $copy = $obj->store_inflated_column($col => $val);

Sets a column value from an inflated value without marking the column
as dirty. This is directly analogous to L<DBIx::Class::Row/store_column>.

=cut

sub store_inflated_column {
  my ($self, $col, $inflated) = @_;
#  unless (blessed $inflated) {
  unless (ref $inflated && ref($inflated) ne 'SCALAR') {
      delete $self->{_inflated_column}{$col};
      $self->store_column($col => $inflated);
      return $inflated;
  }
  delete $self->{_column_data}{$col};
  return $self->{_inflated_column}{$col} = $inflated;
}

=head1 SEE ALSO

=over 4

=item L<DBIx::Class::Core> - This component is loaded as part of the
      C<core> L<DBIx::Class> components; generally there is no need to
      load it directly

=back

=head1 AUTHOR

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 CONTRIBUTORS

Daniel Westermann-Clark <danieltwc@cpan.org> (documentation)

Jess Robinson <cpan@desert-island.demon.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
