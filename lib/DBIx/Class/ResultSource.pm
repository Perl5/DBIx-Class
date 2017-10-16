package DBIx::Class::ResultSource;

### !!!NOTE!!!
#
# Some of the methods defined here will be around()-ed by code at the
# end of ::ResultSourceProxy. The reason for this strange arrangement
# is that the list of around()s of methods in this class depends
# directly on the list of may-not-be-defined-yet methods within
# ::ResultSourceProxy itself.
# If this sounds terrible - it is. But got to work with what we have.
#

use strict;
use warnings;

use base 'DBIx::Class::ResultSource::RowParser';

use DBIx::Class::Carp;
use DBIx::Class::_Util qw(
  UNRESOLVABLE_CONDITION DUMMY_ALIASPAIR
  dbic_internal_try fail_on_internal_call
  refdesc emit_loud_diag dump_value serialize bag_eq
);
use DBIx::Class::SQLMaker::Util qw( normalize_sqla_condition extract_equality_conditions );
use DBIx::Class::ResultSource::FromSpec::Util 'fromspec_columns_info';
use SQL::Abstract 'is_literal_value';
use Devel::GlobalDestruction;
use Scalar::Util qw( blessed weaken isweak refaddr );

# FIXME - somehow breaks ResultSetManager, do not remove until investigated
use DBIx::Class::ResultSet;

use namespace::clean;

# This global is present for the afaik nonexistent, but nevertheless possible
# case of folks using stock ::ResultSet with a completely custom Result-class
# hierarchy, not derived from DBIx::Class::Row at all
# Instead of patching stuff all over the place - this would be one convenient
# place to override things if need be
our $__expected_result_class_isa = 'DBIx::Class::Row';

my @hashref_attributes = qw(
  source_info resultset_attributes
  _columns _unique_constraints _relationships
);
my @arrayref_attributes = qw(
  _ordered_columns _primaries
);
__PACKAGE__->mk_group_accessors(rsrc_instance_specific_attribute =>
  @hashref_attributes,
  @arrayref_attributes,
  qw( source_name name column_info_from_storage sqlt_deploy_callback ),
);

__PACKAGE__->mk_group_accessors(rsrc_instance_specific_handler => qw(
  resultset_class
  result_class
));

=head1 NAME

DBIx::Class::ResultSource - Result source object

=head1 SYNOPSIS

  # Create a table based result source, in a result class.

  package MyApp::Schema::Result::Artist;
  use base qw/DBIx::Class::Core/;

  __PACKAGE__->table('artist');
  __PACKAGE__->add_columns(qw/ artistid name /);
  __PACKAGE__->set_primary_key('artistid');
  __PACKAGE__->has_many(cds => 'MyApp::Schema::Result::CD');

  1;

  # Create a query (view) based result source, in a result class
  package MyApp::Schema::Result::Year2000CDs;
  use base qw/DBIx::Class::Core/;

  __PACKAGE__->load_components('InflateColumn::DateTime');
  __PACKAGE__->table_class('DBIx::Class::ResultSource::View');

  __PACKAGE__->table('year2000cds');
  __PACKAGE__->result_source->is_virtual(1);
  __PACKAGE__->result_source->view_definition(
      "SELECT cdid, artist, title FROM cd WHERE year ='2000'"
      );


=head1 DESCRIPTION

A ResultSource is an object that represents a source of data for querying.

This class is a base class for various specialised types of result
sources, for example L<DBIx::Class::ResultSource::Table>. Table is the
default result source type, so one is created for you when defining a
result class as described in the synopsis above.

More specifically, the L<DBIx::Class::Core> base class pulls in the
L<DBIx::Class::ResultSourceProxy::Table> component, which defines
the L<table|DBIx::Class::ResultSourceProxy::Table/table> method.
When called, C<table> creates and stores an instance of
L<DBIx::Class::ResultSource::Table>. Luckily, to use tables as result
sources, you don't need to remember any of this.

Result sources representing select queries, or views, can also be
created, see L<DBIx::Class::ResultSource::View> for full details.

=head2 Finding result source objects

As mentioned above, a result source instance is created and stored for
you when you define a
L<Result Class|DBIx::Class::Manual::Glossary/Result Class>.

You can retrieve the result source at runtime in the following ways:

=over

=item From a Schema object:

   $schema->source($source_name);

=item From a Result object:

   $result->result_source;

=item From a ResultSet object:

   $rs->result_source;

=back

=head1 METHODS

=head2 new

  $class->new();

  $class->new({attribute_name => value});

Creates a new ResultSource object.  Not normally called directly by end users.

=cut

{
  my $rsrc_registry;

  sub __derived_instances {
    map {
      (defined $_->{weakref})
        ? $_->{weakref}
        : ()
    } values %{ $rsrc_registry->{ refaddr($_[0]) }{ derivatives } }
  }

  sub new {
    my ($class, $attrs) = @_;
    $class = ref $class if ref $class;

    my $ancestor = delete $attrs->{__derived_from};

    my $self = bless { %$attrs }, $class;


    DBIx::Class::_ENV_::ASSERT_NO_ERRONEOUS_METAINSTANCE_USE
      and
    # a constructor with 'name' as sole arg clearly isn't "inheriting" from anything
    ( not ( keys(%$self) == 1 and exists $self->{name} ) )
      and
    defined CORE::caller(1)
      and
    (CORE::caller(1))[3] !~ / ::new$ | ^ DBIx::Class :: (?:
      ResultSourceProxy::Table::table
        |
      ResultSourceProxy::Table::_init_result_source_instance
        |
      ResultSource::clone
    ) $ /x
      and
    local $Carp::CarpLevel = $Carp::CarpLevel + 1
      and
    Carp::confess("Incorrect instantiation of '$self': you almost certainly wanted to call ->clone() instead");


    my $own_slot = $rsrc_registry->{
      my $own_addr = refaddr $self
    } = { derivatives => {} };

    weaken( $own_slot->{weakref} = $self );

    if(
      length ref $ancestor
        and
      my $ancestor_slot = $rsrc_registry->{
        my $ancestor_addr = refaddr $ancestor
      }
    ) {

      # on ancestry recording compact registry slots, prevent unbound growth
      for my $r ( $rsrc_registry, map { $_->{derivatives} } values %$rsrc_registry ) {
        defined $r->{$_}{weakref} or delete $r->{$_}
          for keys %$r;
      }

      weaken( $_->{$own_addr} = $own_slot ) for map
        { $_->{derivatives} }
        (
          $ancestor_slot,
          (grep
            { defined $_->{derivatives}{$ancestor_addr} }
            values %$rsrc_registry
          ),
        )
      ;
    }


    $self->{resultset_class} ||= 'DBIx::Class::ResultSet';
    $self->{name} ||= "!!NAME NOT SET!!";
    $self->{_columns_info_loaded} ||= 0;
    $self->{sqlt_deploy_callback} ||= 'default_sqlt_deploy_hook';

    $self->{$_} = { %{ $self->{$_} || {} } }
      for @hashref_attributes, '__metadata_divergencies';

    $self->{$_} = [ @{ $self->{$_} || [] } ]
      for @arrayref_attributes;

    $self;
  }

  sub DBIx::Class::__Rsrc_Ancestry_iThreads_handler__::CLONE {
    for my $r ( $rsrc_registry, map { $_->{derivatives} } values %$rsrc_registry ) {
      %$r = map {
        defined $_->{weakref}
          ? ( refaddr $_->{weakref} => $_ )
          : ()
      } values %$r
    }
  }


  # needs direct access to $rsrc_registry under an assert
  #
  sub set_rsrc_instance_specific_attribute {

    # only mark if we are setting something different
    if (
      (
        defined( $_[2] )
          xor
        defined( $_[0]->{$_[1]} )
      )
        or
      (
        # both defined
        defined( $_[2] )
          and
        (
          # differ in ref-ness
          (
            length ref( $_[2] )
              xor
            length ref( $_[0]->{$_[1]} )
          )
            or
          # both refs (the mark-on-same-ref is deliberate)
          length ref( $_[2] )
            or
          # both differing strings
          $_[2] ne $_[0]->{$_[1]}
        )
      )
    ) {

      my $callsite;
      # need to protect $_ here
      for my $derivative (
        $_[0]->__derived_instances,

        # DO NOT REMOVE - this blob is marking *ancestors* as tainted, here to
        # weed  out any fallout from https://github.com/dbsrgits/dbix-class/commit/9e36e3ec
        # Note that there is no way to kill this warning, aside from never
        # calling set_primary_key etc more than once per hierarchy
        # (this is why the entire thing is guarded by an assert)
        (
          (
            DBIx::Class::_ENV_::ASSERT_NO_ERRONEOUS_METAINSTANCE_USE
              and
            grep { $_[1] eq $_ } qw( _unique_constraints _primaries source_info )
          )
          ? (
            map
              { defined($_->{weakref}) ? $_->{weakref} : () }
              grep
                { defined( ( $_->{derivatives}{refaddr($_[0])} || {} )->{weakref} ) }
                values %$rsrc_registry
          )
          : ()
        ),
      ) {

        $derivative->{__metadata_divergencies}{$_[1]}{ $callsite ||= do {

          #
          # FIXME - this is horrible, but it's the best we can do for now
          # Replace when Carp::Skip is written (it *MUST* take this use-case
          # into consideration)
          #
          my ($cs) = DBIx::Class::Carp::__find_caller(__PACKAGE__);

          my ($fr_num, @fr) = 1;
          while( @fr = CORE::caller($fr_num++) ) {
            $cs =~ /^ \Qat $fr[1] line $fr[2]\E (?: $ | \n )/x
              and
            $fr[3] =~ s/.+:://
              and
            last
          }

          # FIXME - using refdesc here isn't great, but I can't think of anything
          # better at this moment
          @fr
            ? "@{[ refdesc $_[0] ]}->$fr[3](...) $cs"
            : "$cs"
          ;
        } } = 1;
      }
    }

    $_[0]->{$_[1]} = $_[2];
  }
}

sub get_rsrc_instance_specific_attribute {

  $_[0]->__emit_stale_metadata_diag( $_[1] ) if (
    ! $_[0]->{__in_rsrc_setter_callstack}
      and
    $_[0]->{__metadata_divergencies}{$_[1]}
  );

  $_[0]->{$_[1]};
}


# reuse the elaborate set logic of instance_specific_attr
sub set_rsrc_instance_specific_handler {
  $_[0]->set_rsrc_instance_specific_attribute($_[1], $_[2]);

  # trigger a load for the case of $foo->handler_accessor("bar")->new
  $_[0]->get_rsrc_instance_specific_handler($_[1])
    if defined wantarray;
}

# This is essentially the same logic as get_component_class
# (in DBIC::AccessorGroup). However the latter is a grouped
# accessor type, and here we are strictly after a 'simple'
# So we go ahead and recreate the logic as found in ::AG
sub get_rsrc_instance_specific_handler {

  # emit desync warnings if any
  my $val = $_[0]->get_rsrc_instance_specific_attribute( $_[1] );

  # plain string means class - load it
  no strict 'refs';
  if (
    defined $val
      and
    # inherited CAG can't be set to undef effectively, so people may use ''
    length $val
      and
    ! defined blessed $val
      and
    ! ${"${val}::__LOADED__BY__DBIC__CAG__COMPONENT_CLASS__"}
  ) {
    $_[0]->ensure_class_loaded($val);

    ${"${val}::__LOADED__BY__DBIC__CAG__COMPONENT_CLASS__"}
      = do { \(my $anon = 'loaded') };
  }

  $val;
}


sub __construct_stale_metadata_diag {
  return '' unless $_[0]->{__metadata_divergencies}{$_[1]};

  my ($fr_num, @fr);

  # find the CAG getter FIRST
  # allows unlimited user-namespace overrides without screwing around with
  # $LEVEL-like crap
  while(
    @fr = CORE::caller(++$fr_num)
      and
    $fr[3] ne 'DBIx::Class::ResultSource::get_rsrc_instance_specific_attribute'
  ) { 1 }

  Carp::confess( "You are not supposed to call __construct_stale_metadata_diag here..." )
    unless @fr;

  # then find the first non-local, non-private reportable callsite
  while (
    @fr = CORE::caller(++$fr_num)
      and
    (
      $fr[2] == 0
        or
      $fr[3] eq '(eval)'
        or
      $fr[1] =~ /^\(eval \d+\)$/
        or
      $fr[3] =~ /::(?: __ANON__ | _\w+ )$/x
        or
      $fr[0] =~ /^DBIx::Class::ResultSource/
    )
  ) { 1 }

  my $by = ( @fr and $fr[3] =~ s/.+::// )
    # FIXME - using refdesc here isn't great, but I can't think of anything
    # better at this moment
    ? " by 'getter' @{[ refdesc $_[0] ]}->$fr[3](...)\n  within the callstack beginning"
    : ''
  ;

  # Given the full stacktrace combined with the really involved callstack
  # there is no chance the emitter will properly deduplicate this
  # Only complain once per callsite per source
  return( ( $by and $_[0]->{__encountered_divergencies}{$by}++ )

    ? ''

    : "$_[0] (the metadata instance of source '@{[ $_[0]->source_name ]}') is "
    . "*OUTDATED*, and does not reflect the modifications of its "
    . "*ancestors* as follows:\n"
    . join( "\n",
        map
          { "  * $_->[0]" }
          sort
            { $a->[1] cmp $b->[1] }
            map
              { [ $_, ( $_ =~ /( at .+? line \d+)/ ) ] }
              keys %{ $_[0]->{__metadata_divergencies}{$_[1]} }
      )
    . "\nStale metadata accessed${by}"
  );
}

sub __emit_stale_metadata_diag {
  emit_loud_diag(
    msg => (
      # short circuit: no message - no diag
      $_[0]->__construct_stale_metadata_diag($_[1])
        ||
      return 0
    ),
    # the constructor already does deduplication
    emit_dups => 1,
    confess => DBIx::Class::_ENV_::ASSERT_NO_ERRONEOUS_METAINSTANCE_USE,
  );
}

=head2 clone

  $rsrc_instance->clone( atribute_name => overridden_value );

A wrapper around L</new> inheriting any defaults from the callee. This method
also not normally invoked directly by end users.

=cut

sub clone {
  my $self = shift;

  $self->new({
    (
      (length ref $self)
        ? ( %$self, __derived_from => $self )
        : ()
    ),
    (
      (@_ == 1 and ref $_[0] eq 'HASH')
        ? %{ $_[0] }
        : @_
    ),
  });
}

=pod

=head2 add_columns

=over

=item Arguments: @columns

=item Return Value: L<$result_source|/new>

=back

  $source->add_columns(qw/col1 col2 col3/);

  $source->add_columns('col1' => \%col1_info, 'col2' => \%col2_info, ...);

  $source->add_columns(
    'col1' => { data_type => 'integer', is_nullable => 1, ... },
    'col2' => { data_type => 'text',    is_auto_increment => 1, ... },
  );

Adds columns to the result source. If supplied colname => hashref
pairs, uses the hashref as the L</column_info> for that column. Repeated
calls of this method will add more columns, not replace them.

The column names given will be created as accessor methods on your
L<Result|DBIx::Class::Manual::ResultClass> objects. You can change the name of the accessor
by supplying an L</accessor> in the column_info hash.

If a column name beginning with a plus sign ('+col1') is provided, the
attributes provided will be merged with any existing attributes for the
column, with the new attributes taking precedence in the case that an
attribute already exists. Using this without a hashref
(C<< $source->add_columns(qw/+col1 +col2/) >>) is legal, but useless --
it does the same thing it would do without the plus.

The contents of the column_info are not set in stone. The following
keys are currently recognised/used by DBIx::Class:

=over 4

=item accessor

   { accessor => '_name' }

   # example use, replace standard accessor with one of your own:
   sub name {
       my ($self, $value) = @_;

       die "Name cannot contain digits!" if($value =~ /\d/);
       $self->_name($value);

       return $self->_name();
   }

Use this to set the name of the accessor method for this column. If unset,
the name of the column will be used.

=item data_type

   { data_type => 'integer' }

This contains the column type. It is automatically filled if you use the
L<SQL::Translator::Producer::DBIx::Class::File> producer, or the
L<DBIx::Class::Schema::Loader> module.

Currently there is no standard set of values for the data_type. Use
whatever your database supports.

=item size

   { size => 20 }

The length of your column, if it is a column type that can have a size
restriction. This is currently only used to create tables from your
schema, see L<DBIx::Class::Schema/deploy>.

   { size => [ 9, 6 ] }

For decimal or float values you can specify an ArrayRef in order to
control precision, assuming your database's
L<SQL::Translator::Producer> supports it.

=item is_nullable

   { is_nullable => 1 }

Set this to a true value for a column that is allowed to contain NULL
values, default is false. This is currently only used to create tables
from your schema, see L<DBIx::Class::Schema/deploy>.

=item is_auto_increment

   { is_auto_increment => 1 }

Set this to a true value for a column whose value is somehow
automatically set, defaults to false. This is used to determine which
columns to empty when cloning objects using
L<DBIx::Class::Row/copy>. It is also used by
L<DBIx::Class::Schema/deploy>.

=item is_numeric

   { is_numeric => 1 }

Set this to a true or false value (not C<undef>) to explicitly specify
if this column contains numeric data. This controls how set_column
decides whether to consider a column dirty after an update: if
C<is_numeric> is true a numeric comparison C<< != >> will take place
instead of the usual C<eq>

If not specified the storage class will attempt to figure this out on
first access to the column, based on the column C<data_type>. The
result will be cached in this attribute.

=item is_foreign_key

   { is_foreign_key => 1 }

Set this to a true value for a column that contains a key from a
foreign table, defaults to false. This is currently only used to
create tables from your schema, see L<DBIx::Class::Schema/deploy>.

=item default_value

   { default_value => \'now()' }

Set this to the default value which will be inserted into a column by
the database. Can contain either a value or a function (use a
reference to a scalar e.g. C<\'now()'> if you want a function). This
is currently only used to create tables from your schema, see
L<DBIx::Class::Schema/deploy>.

See the note on L<DBIx::Class::Row/new> for more information about possible
issues related to db-side default values.

=item sequence

   { sequence => 'my_table_seq' }

Set this on a primary key column to the name of the sequence used to
generate a new key value. If not specified, L<DBIx::Class::PK::Auto>
will attempt to retrieve the name of the sequence from the database
automatically.

=item retrieve_on_insert

  { retrieve_on_insert => 1 }

For every column where this is set to true, DBIC will retrieve the RDBMS-side
value upon a new row insertion (normally only the autoincrement PK is
retrieved on insert). C<INSERT ... RETURNING> is used automatically if
supported by the underlying storage, otherwise an extra SELECT statement is
executed to retrieve the missing data.

=item auto_nextval

   { auto_nextval => 1 }

Set this to a true value for a column whose value is retrieved automatically
from a sequence or function (if supported by your Storage driver.) For a
sequence, if you do not use a trigger to get the nextval, you have to set the
L</sequence> value as well.

Also set this for MSSQL columns with the 'uniqueidentifier'
L<data_type|DBIx::Class::ResultSource/data_type> whose values you want to
automatically generate using C<NEWID()>, unless they are a primary key in which
case this will be done anyway.

=item extra

This is used by L<DBIx::Class::Schema/deploy> and L<SQL::Translator>
to add extra non-generic data to the column. For example: C<< extra
=> { unsigned => 1} >> is used by the MySQL producer to set an integer
column to unsigned. For more details, see
L<SQL::Translator::Producer::MySQL>.

=back

=head2 add_column

=over

=item Arguments: $colname, \%columninfo?

=item Return Value: 1/0 (true/false)

=back

  $source->add_column('col' => \%info);

Add a single column and optional column info. Uses the same column
info keys as L</add_columns>.

=cut

sub add_columns {
  my ($self, @cols) = @_;

  local $self->{__in_rsrc_setter_callstack} = 1
    unless $self->{__in_rsrc_setter_callstack};

  $self->_ordered_columns(\@cols) unless $self->_ordered_columns;

  my ( @added, $colinfos );
  my $columns = $self->_columns;

  while (my $col = shift @cols) {
    my $column_info =
      (
        $col =~ s/^\+//
          and
        ( $colinfos ||= $self->columns_info )->{$col}
      )
        ||
      {}
    ;

    # If next entry is { ... } use that for the column info, if not
    # use an empty hashref
    if (ref $cols[0]) {
      my $new_info = shift(@cols);
      %$column_info = (%$column_info, %$new_info);
    }
    push(@added, $col) unless exists $columns->{$col};
    $columns->{$col} = $column_info;
  }

  push @{ $self->_ordered_columns }, @added;
  $self->_columns($columns);
  return $self;
}

sub add_column :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->add_columns(@_)
}

=head2 has_column

=over

=item Arguments: $colname

=item Return Value: 1/0 (true/false)

=back

  if ($source->has_column($colname)) { ... }

Returns true if the source has a column of this name, false otherwise.

=cut

sub has_column {
  my ($self, $column) = @_;
  return exists $self->_columns->{$column};
}

=head2 column_info

=over

=item Arguments: $colname

=item Return Value: Hashref of info

=back

  my $info = $source->column_info($col);

Returns the column metadata hashref for a column, as originally passed
to L</add_columns>. See L</add_columns> above for information on the
contents of the hashref.

=cut

sub column_info :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;

  #my ($self, $column) = @_;
  $_[0]->columns_info([ $_[1] ])->{$_[1]};
}

=head2 columns

=over

=item Arguments: none

=item Return Value: Ordered list of column names

=back

  my @column_names = $source->columns;

Returns all column names in the order they were declared to L</add_columns>.

=cut

sub columns {
  my $self = shift;
  $self->throw_exception(
    "columns() is a read-only accessor, did you mean add_columns()?"
  ) if @_;
  return @{$self->{_ordered_columns}||[]};
}

=head2 columns_info

=over

=item Arguments: \@colnames ?

=item Return Value: Hashref of column name/info pairs

=back

  my $columns_info = $source->columns_info;

Like L</column_info> but returns information for the requested columns. If
the optional column-list arrayref is omitted it returns info on all columns
currently defined on the ResultSource via L</add_columns>.

=cut

sub columns_info {
  my ($self, $columns) = @_;

  my $colinfo = $self->_columns;

  if (
    ! $self->{_columns_info_loaded}
      and
    $self->column_info_from_storage
      and
    grep { ! $_->{data_type} } values %$colinfo
      and
    my $stor = dbic_internal_try { $self->schema->storage }
  ) {
    $self->{_columns_info_loaded}++;

    # try for the case of storage without table
    dbic_internal_try {
      my $info = $stor->columns_info_for( $self->from );
      my $lc_info = { map
        { (lc $_) => $info->{$_} }
        ( keys %$info )
      };

      foreach my $col ( keys %$colinfo ) {
        $colinfo->{$col} = {
          %{ $colinfo->{$col} },
          %{ $info->{$col} || $lc_info->{lc $col} || {} }
        };
      }
    };
  }

  my %ret;

  if ($columns) {
    for (@$columns) {
      if (my $inf = $colinfo->{$_}) {
        $ret{$_} = $inf;
      }
      else {
        $self->throw_exception( sprintf (
          "No such column '%s' on source '%s'",
          $_,
          $self->source_name || $self->name || 'Unknown source...?',
        ));
      }
    }
  }
  else {
    # the shallow copy is crucial - there are exists() checks within
    # the wider codebase
    %ret = %$colinfo;
  }

  return \%ret;
}

=head2 remove_columns

=over

=item Arguments: @colnames

=item Return Value: not defined

=back

  $source->remove_columns(qw/col1 col2 col3/);

Removes the given list of columns by name, from the result source.

B<Warning>: Removing a column that is also used in the sources primary
key, or in one of the sources unique constraints, B<will> result in a
broken result source.

=head2 remove_column

=over

=item Arguments: $colname

=item Return Value: not defined

=back

  $source->remove_column('col');

Remove a single column by name from the result source, similar to
L</remove_columns>.

B<Warning>: Removing a column that is also used in the sources primary
key, or in one of the sources unique constraints, B<will> result in a
broken result source.

=cut

sub remove_columns {
  my ($self, @to_remove) = @_;

  local $self->{__in_rsrc_setter_callstack} = 1
    unless $self->{__in_rsrc_setter_callstack};

  my $columns = $self->_columns
    or return;

  my %to_remove;
  for (@to_remove) {
    delete $columns->{$_};
    ++$to_remove{$_};
  }

  $self->_ordered_columns([ grep { not $to_remove{$_} } @{$self->_ordered_columns} ]);
}

sub remove_column :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->remove_columns(@_)
}

=head2 set_primary_key

=over 4

=item Arguments: @cols

=item Return Value: not defined

=back

Defines one or more columns as primary key for this source. Must be
called after L</add_columns>.

Additionally, defines a L<unique constraint|/add_unique_constraint>
named C<primary>.

Note: you normally do want to define a primary key on your sources
B<even if the underlying database table does not have a primary key>.
See
L<DBIx::Class::Manual::Intro/The Significance and Importance of Primary Keys>
for more info.

=cut

sub set_primary_key {
  my ($self, @cols) = @_;

  local $self->{__in_rsrc_setter_callstack} = 1
    unless $self->{__in_rsrc_setter_callstack};

  my $colinfo = $self->columns_info(\@cols);
  for my $col (@cols) {
    carp_unique(sprintf (
      "Primary key of source '%s' includes the column '%s' which has its "
    . "'is_nullable' attribute set to true. This is a mistake and will cause "
    . 'various Result-object operations to fail',
      $self->source_name || $self->name || 'Unknown source...?',
      $col,
    )) if $colinfo->{$col}{is_nullable};
  }

  $self->_primaries(\@cols);

  $self->add_unique_constraint(primary => \@cols);
}

=head2 primary_columns

=over 4

=item Arguments: none

=item Return Value: Ordered list of primary column names

=back

Read-only accessor which returns the list of primary keys, supplied by
L</set_primary_key>.

=cut

sub primary_columns {
  return @{shift->_primaries||[]};
}

# a helper method that will automatically die with a descriptive message if
# no pk is defined on the source in question. For internal use to save
# on if @pks... boilerplate
sub _pri_cols_or_die {
  my $self = shift;
  my @pcols = $self->primary_columns
    or $self->throw_exception (sprintf(
      "Operation requires a primary key to be declared on '%s' via set_primary_key",
      # source_name is set only after schema-registration
      $self->source_name || $self->result_class || $self->name || 'Unknown source...?',
    ));
  return @pcols;
}

# same as above but mandating single-column PK (used by relationship condition
# inference)
sub _single_pri_col_or_die {
  my $self = shift;
  my ($pri, @too_many) = $self->_pri_cols_or_die;

  $self->throw_exception( sprintf(
    "Operation requires a single-column primary key declared on '%s'",
    $self->source_name || $self->result_class || $self->name || 'Unknown source...?',
  )) if @too_many;
  return $pri;
}


=head2 sequence

Manually define the correct sequence for your table, to avoid the overhead
associated with looking up the sequence automatically. The supplied sequence
will be applied to the L</column_info> of each L<primary_key|/set_primary_key>

=over 4

=item Arguments: $sequence_name

=item Return Value: not defined

=back

=cut

sub sequence {
  my ($self,$seq) = @_;

  local $self->{__in_rsrc_setter_callstack} = 1
    unless $self->{__in_rsrc_setter_callstack};

  my @pks = $self->primary_columns
    or return;

  $_->{sequence} = $seq
    for values %{ $self->columns_info (\@pks) };
}


=head2 add_unique_constraint

=over 4

=item Arguments: $name?, \@colnames

=item Return Value: not defined

=back

Declare a unique constraint on this source. Call once for each unique
constraint.

  # For UNIQUE (column1, column2)
  __PACKAGE__->add_unique_constraint(
    constraint_name => [ qw/column1 column2/ ],
  );

Alternatively, you can specify only the columns:

  __PACKAGE__->add_unique_constraint([ qw/column1 column2/ ]);

This will result in a unique constraint named
C<table_column1_column2>, where C<table> is replaced with the table
name.

Unique constraints are used, for example, when you pass the constraint
name as the C<key> attribute to L<DBIx::Class::ResultSet/find>. Then
only columns in the constraint are searched.

Throws an error if any of the given column names do not yet exist on
the result source.

=cut

sub add_unique_constraint {
  my $self = shift;

  local $self->{__in_rsrc_setter_callstack} = 1
    unless $self->{__in_rsrc_setter_callstack};

  if (@_ > 2) {
    $self->throw_exception(
        'add_unique_constraint() does not accept multiple constraints, use '
      . 'add_unique_constraints() instead'
    );
  }

  my $cols = pop @_;
  if (ref $cols ne 'ARRAY') {
    $self->throw_exception (
      'Expecting an arrayref of constraint columns, got ' . ($cols||'NOTHING')
    );
  }

  my $name = shift @_;

  $name ||= $self->name_unique_constraint($cols);

  foreach my $col (@$cols) {
    $self->throw_exception("No such column $col on table " . $self->name)
      unless $self->has_column($col);
  }

  my %unique_constraints = $self->unique_constraints;
  $unique_constraints{$name} = $cols;
  $self->_unique_constraints(\%unique_constraints);
}

=head2 add_unique_constraints

=over 4

=item Arguments: @constraints

=item Return Value: not defined

=back

Declare multiple unique constraints on this source.

  __PACKAGE__->add_unique_constraints(
    constraint_name1 => [ qw/column1 column2/ ],
    constraint_name2 => [ qw/column2 column3/ ],
  );

Alternatively, you can specify only the columns:

  __PACKAGE__->add_unique_constraints(
    [ qw/column1 column2/ ],
    [ qw/column3 column4/ ]
  );

This will result in unique constraints named C<table_column1_column2> and
C<table_column3_column4>, where C<table> is replaced with the table name.

Throws an error if any of the given column names do not yet exist on
the result source.

See also L</add_unique_constraint>.

=cut

sub add_unique_constraints :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;

  my $self = shift;
  my @constraints = @_;

  if ( !(@constraints % 2) && grep { ref $_ ne 'ARRAY' } @constraints ) {
    # with constraint name
    while (my ($name, $constraint) = splice @constraints, 0, 2) {
      $self->add_unique_constraint($name => $constraint);
    }
  }
  else {
    # no constraint name
    foreach my $constraint (@constraints) {
      $self->add_unique_constraint($constraint);
    }
  }
}

=head2 name_unique_constraint

=over 4

=item Arguments: \@colnames

=item Return Value: Constraint name

=back

  $source->table('mytable');
  $source->name_unique_constraint(['col1', 'col2']);
  # returns
  'mytable_col1_col2'

Return a name for a unique constraint containing the specified
columns. The name is created by joining the table name and each column
name, using an underscore character.

For example, a constraint on a table named C<cd> containing the columns
C<artist> and C<title> would result in a constraint name of C<cd_artist_title>.

This is used by L</add_unique_constraint> if you do not specify the
optional constraint name.

=cut

sub name_unique_constraint {
  my ($self, $cols) = @_;

  my $name = $self->name;
  $name = $$name if (ref $name eq 'SCALAR');
  $name =~ s/ ^ [^\.]+ \. //x;  # strip possible schema qualifier

  return join '_', $name, @$cols;
}

=head2 unique_constraints

=over 4

=item Arguments: none

=item Return Value: Hash of unique constraint data

=back

  $source->unique_constraints();

Read-only accessor which returns a hash of unique constraints on this
source.

The hash is keyed by constraint name, and contains an arrayref of
column names as values.

=cut

sub unique_constraints {
  return %{shift->_unique_constraints||{}};
}

=head2 unique_constraint_names

=over 4

=item Arguments: none

=item Return Value: Unique constraint names

=back

  $source->unique_constraint_names();

Returns the list of unique constraint names defined on this source.

=cut

sub unique_constraint_names {
  my ($self) = @_;

  my %unique_constraints = $self->unique_constraints;

  return keys %unique_constraints;
}

=head2 unique_constraint_columns

=over 4

=item Arguments: $constraintname

=item Return Value: List of constraint columns

=back

  $source->unique_constraint_columns('myconstraint');

Returns the list of columns that make up the specified unique constraint.

=cut

sub unique_constraint_columns {
  my ($self, $constraint_name) = @_;

  my %unique_constraints = $self->unique_constraints;

  $self->throw_exception(
    "Unknown unique constraint $constraint_name on '" . $self->name . "'"
  ) unless exists $unique_constraints{$constraint_name};

  return @{ $unique_constraints{$constraint_name} };
}

=head2 sqlt_deploy_callback

=over

=item Arguments: $callback_name | \&callback_code

=item Return Value: $callback_name | \&callback_code

=back

  __PACKAGE__->result_source->sqlt_deploy_callback('mycallbackmethod');

   or

  __PACKAGE__->result_source->sqlt_deploy_callback(sub {
    my ($source_instance, $sqlt_table) = @_;
    ...
  } );

An accessor to set a callback to be called during deployment of
the schema via L<DBIx::Class::Schema/create_ddl_dir> or
L<DBIx::Class::Schema/deploy>.

The callback can be set as either a code reference or the name of a
method in the current result class.

Defaults to L</default_sqlt_deploy_hook>.

Your callback will be passed the $source object representing the
ResultSource instance being deployed, and the
L<SQL::Translator::Schema::Table> object being created from it. The
callback can be used to manipulate the table object or add your own
customised indexes. If you need to manipulate a non-table object, use
the L<DBIx::Class::Schema/sqlt_deploy_hook>.

See L<DBIx::Class::Manual::Cookbook/Adding Indexes And Functions To
Your SQL> for examples.

This sqlt deployment callback can only be used to manipulate
SQL::Translator objects as they get turned into SQL. To execute
post-deploy statements which SQL::Translator does not currently
handle, override L<DBIx::Class::Schema/deploy> in your Schema class
and call L<dbh_do|DBIx::Class::Storage::DBI/dbh_do>.

=head2 default_sqlt_deploy_hook

This is the default deploy hook implementation which checks if your
current Result class has a C<sqlt_deploy_hook> method, and if present
invokes it B<on the Result class directly>. This is to preserve the
semantics of C<sqlt_deploy_hook> which was originally designed to expect
the Result class name and the
L<$sqlt_table instance|SQL::Translator::Schema::Table> of the table being
deployed.

=cut

sub default_sqlt_deploy_hook {
  my $self = shift;

  my $class = $self->result_class;

  if ($class and $class->can('sqlt_deploy_hook')) {
    $class->sqlt_deploy_hook(@_);
  }
}

sub _invoke_sqlt_deploy_hook {
  my $self = shift;
  if ( my $hook = $self->sqlt_deploy_callback) {
    $self->$hook(@_);
  }
}

=head2 result_class

=over 4

=item Arguments: $classname

=item Return Value: $classname

=back

 use My::Schema::ResultClass::Inflator;
 ...

 use My::Schema::Artist;
 ...
 __PACKAGE__->result_class('My::Schema::ResultClass::Inflator');

Set the default result class for this source. You can use this to create
and use your own result inflator. See L<DBIx::Class::ResultSet/result_class>
for more details.

Please note that setting this to something like
L<DBIx::Class::ResultClass::HashRefInflator> will make every result unblessed
and make life more difficult.  Inflators like those are better suited to
temporary usage via L<DBIx::Class::ResultSet/result_class>.

=head2 resultset

=over 4

=item Arguments: none

=item Return Value: L<$resultset|DBIx::Class::ResultSet>

=back

Returns a resultset for the given source. This will initially be created
on demand by calling

  $self->resultset_class->new($self, $self->resultset_attributes)

but is cached from then on unless resultset_class changes.

=head2 resultset_class

=over 4

=item Arguments: $classname

=item Return Value: $classname

=back

  package My::Schema::ResultSet::Artist;
  use base 'DBIx::Class::ResultSet';
  ...

  # In the result class
  __PACKAGE__->resultset_class('My::Schema::ResultSet::Artist');

  # Or in code
  $source->resultset_class('My::Schema::ResultSet::Artist');

Set the class of the resultset. This is useful if you want to create your
own resultset methods. Create your own class derived from
L<DBIx::Class::ResultSet>, and set it here. If called with no arguments,
this method returns the name of the existing resultset class, if one
exists.

=head2 resultset_attributes

=over 4

=item Arguments: L<\%attrs|DBIx::Class::ResultSet/ATTRIBUTES>

=item Return Value: L<\%attrs|DBIx::Class::ResultSet/ATTRIBUTES>

=back

  # In the result class
  __PACKAGE__->resultset_attributes({ order_by => [ 'id' ] });

  # Or in code
  $source->resultset_attributes({ order_by => [ 'id' ] });

Store a collection of resultset attributes, that will be set on every
L<DBIx::Class::ResultSet> produced from this result source.

B<CAVEAT>: C<resultset_attributes> comes with its own set of issues and
bugs! Notably the contents of the attributes are B<entirely static>, which
greatly hinders composability (things like L<current_source_alias
|DBIx::Class::ResultSet/current_source_alias> can not possibly be respected).
While C<resultset_attributes> isn't deprecated per se, you are strongly urged
to seek alternatives.

Since relationships use attributes to link tables together, the "default"
attributes you set may cause unpredictable and undesired behavior.  Furthermore,
the defaults B<cannot be turned off>, so you are stuck with them.

In most cases, what you should actually be using are project-specific methods:

  package My::Schema::ResultSet::Artist;
  use base 'DBIx::Class::ResultSet';
  ...

  # BAD IDEA!
  #__PACKAGE__->resultset_attributes({ prefetch => 'tracks' });

  # GOOD IDEA!
  sub with_tracks { shift->search({}, { prefetch => 'tracks' }) }

  # in your code
  $schema->resultset('Artist')->with_tracks->...

This gives you the flexibility of not using it when you don't need it.

For more complex situations, another solution would be to use a virtual view
via L<DBIx::Class::ResultSource::View>.

=cut

sub resultset {
  my $self = shift;
  $self->throw_exception(
    'resultset does not take any arguments. If you want another resultset, '.
    'call it on the schema instead.'
  ) if scalar @_;

  $self->resultset_class->new(
    $self,
    {
      ( dbic_internal_try { %{$self->schema->default_resultset_attributes} } ),
      %{$self->{resultset_attributes}},
    },
  );
}

=head2 name

=over 4

=item Arguments: none

=item Result value: $name

=back

Returns the name of the result source, which will typically be the table
name. This may be a scalar reference if the result source has a non-standard
name.

=head2 source_name

=over 4

=item Arguments: $source_name

=item Result value: $source_name

=back

Set an alternate name for the result source when it is loaded into a schema.
This is useful if you want to refer to a result source by a name other than
its class name.

  package ArchivedBooks;
  use base qw/DBIx::Class/;
  __PACKAGE__->table('books_archive');
  __PACKAGE__->source_name('Books');

  # from your schema...
  $schema->resultset('Books')->find(1);

=head2 from

=over 4

=item Arguments: none

=item Return Value: FROM clause

=back

  my $from_clause = $source->from();

Returns an expression of the source to be supplied to storage to specify
retrieval from this source. In the case of a database, the required FROM
clause contents.

=cut

sub from { die 'Virtual method!' }

=head2 source_info

Stores a hashref of per-source metadata.  No specific key names
have yet been standardized, the examples below are purely hypothetical
and don't actually accomplish anything on their own:

  __PACKAGE__->source_info({
    "_tablespace" => 'fast_disk_array_3',
    "_engine" => 'InnoDB',
  });

=head2 schema

=over 4

=item Arguments: L<$schema?|DBIx::Class::Schema>

=item Return Value: L<$schema|DBIx::Class::Schema>

=back

  my $schema = $source->schema();

Sets and/or returns the L<DBIx::Class::Schema> object to which this
result source instance has been attached to.

=cut

sub schema {
  if (@_ > 1) {
    # invoke the mark-diverging logic
    $_[0]->set_rsrc_instance_specific_attribute( schema => $_[1] );
  }
  else {
    $_[0]->get_rsrc_instance_specific_attribute( 'schema' ) || do {
      my $name = $_[0]->{source_name} || '_unnamed_';
      my $err = 'Unable to perform storage-dependent operations with a detached result source '
              . "(source '$name' is not associated with a schema).";

      $err .= ' You need to use $schema->thaw() or manually set'
            . ' $DBIx::Class::ResultSourceHandle::thaw_schema while thawing.'
        if $_[0]->{_detached_thaw};

      DBIx::Class::Exception->throw($err);
    };
  }
}

=head2 storage

=over 4

=item Arguments: none

=item Return Value: L<$storage|DBIx::Class::Storage>

=back

  $source->storage->debug(1);

Returns the L<storage handle|DBIx::Class::Storage> for the current schema.

=cut

sub storage :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  $_[0]->schema->storage
}

=head2 add_relationship

=over 4

=item Arguments: $rel_name, $related_source_name, \%cond, \%attrs?

=item Return Value: 1/true if it succeeded

=back

  $source->add_relationship('rel_name', 'related_source', $cond, $attrs);

L<DBIx::Class::Relationship> describes a series of methods which
create pre-defined useful types of relationships. Look there first
before using this method directly.

The relationship name can be arbitrary, but must be unique for each
relationship attached to this result source. 'related_source' should
be the name with which the related result source was registered with
the current schema. For example:

  $schema->source('Book')->add_relationship('reviews', 'Review', {
    'foreign.book_id' => 'self.id',
  });

The condition C<$cond> needs to be an L<SQL::Abstract>-style
representation of the join between the tables. For example, if you're
creating a relation from Author to Book,

  { 'foreign.author_id' => 'self.id' }

will result in the JOIN clause

  author me JOIN book foreign ON foreign.author_id = me.id

You can specify as many foreign => self mappings as necessary.

Valid attributes are as follows:

=over 4

=item join_type

Explicitly specifies the type of join to use in the relationship. Any
SQL join type is valid, e.g. C<LEFT> or C<RIGHT>. It will be placed in
the SQL command immediately before C<JOIN>.

=item proxy

An arrayref containing a list of accessors in the foreign class to proxy in
the main class. If, for example, you do the following:

  CD->might_have(liner_notes => 'LinerNotes', undef, {
    proxy => [ qw/notes/ ],
  });

Then, assuming LinerNotes has an accessor named notes, you can do:

  my $cd = CD->find(1);
  # set notes -- LinerNotes object is created if it doesn't exist
  $cd->notes('Notes go here');

=item accessor

Specifies the type of accessor that should be created for the
relationship. Valid values are C<single> (for when there is only a single
related object), C<multi> (when there can be many), and C<filter> (for
when there is a single related object, but you also want the relationship
accessor to double as a column accessor). For C<multi> accessors, an
add_to_* method is also created, which calls C<create_related> for the
relationship.

=back

Throws an exception if the condition is improperly supplied, or cannot
be resolved.

=cut

sub add_relationship {
  my ($self, $rel, $f_source_name, $cond, $attrs) = @_;

  local $self->{__in_rsrc_setter_callstack} = 1
    unless $self->{__in_rsrc_setter_callstack};

  $self->throw_exception("Can't create relationship without join condition")
    unless $cond;
  $attrs ||= {};

  # Check foreign and self are right in cond
  if ( (ref $cond ||'') eq 'HASH') {
    $_ =~ /^foreign\./ or $self->throw_exception("Malformed relationship condition key '$_': must be prefixed with 'foreign.'")
      for keys %$cond;

    $_ =~ /^self\./ or $self->throw_exception("Malformed relationship condition value '$_': must be prefixed with 'self.'")
      for values %$cond;
  }

  my %rels = %{ $self->_relationships };
  $rels{$rel} = { class => $f_source_name,
                  source => $f_source_name,
                  cond  => $cond,
                  attrs => $attrs };
  $self->_relationships(\%rels);

  return $self;
}

=head2 relationships

=over 4

=item Arguments: none

=item Return Value: L<@rel_names|DBIx::Class::Relationship>

=back

  my @rel_names = $source->relationships();

Returns all relationship names for this source.

=cut

sub relationships {
  keys %{$_[0]->_relationships};
}

=head2 relationship_info

=over 4

=item Arguments: L<$rel_name|DBIx::Class::Relationship>

=item Return Value: L<\%rel_data|DBIx::Class::Relationship::Base/add_relationship>

=back

Returns a hash of relationship information for the specified relationship
name. The keys/values are as specified for L<DBIx::Class::Relationship::Base/add_relationship>.

=cut

sub relationship_info {
  #my ($self, $rel) = @_;
  return shift->_relationships->{+shift};
}

=head2 has_relationship

=over 4

=item Arguments: L<$rel_name|DBIx::Class::Relationship>

=item Return Value: 1/0 (true/false)

=back

Returns true if the source has a relationship of this name, false otherwise.

=cut

sub has_relationship {
  #my ($self, $rel) = @_;
  return exists shift->_relationships->{+shift};
}

=head2 reverse_relationship_info

=over 4

=item Arguments: L<$rel_name|DBIx::Class::Relationship>

=item Return Value: L<\%rel_data|DBIx::Class::Relationship::Base/add_relationship>

=back

Looks through all the relationships on the source this relationship
points to, looking for one whose condition is the reverse of the
condition on this relationship.

A common use of this is to find the name of the C<belongs_to> relation
opposing a C<has_many> relation. For definition of these look in
L<DBIx::Class::Relationship>.

The returned hashref is keyed by the name of the opposing
relationship, and contains its data in the same manner as
L</relationship_info>.

=cut

sub reverse_relationship_info {
  my ($self, $rel) = @_;

  # This may be a partial schema or something else equally esoteric
  # in which case this will throw
  #
  my $other_rsrc = $self->related_source($rel);

  # Some custom rels may not resolve without a $schema
  #
  my $our_resolved_relcond = dbic_internal_try {
    $self->resolve_relationship_condition(
      rel_name => $rel,

      # an API where these are optional would be too cumbersome,
      # instead always pass in some dummy values
      DUMMY_ALIASPAIR,
    )
  };

  # only straight-equality is compared
  return {}
    unless $our_resolved_relcond->{identity_map_matches_condition};

  my( $our_registered_source_name, $our_result_class) =
    ( $self->source_name, $self->result_class );

  my $ret = {};

  # Get all the relationships for that source that related to this source
  # whose foreign column set are our self columns on $rel and whose self
  # columns are our foreign columns on $rel
  foreach my $other_rel ($other_rsrc->relationships) {

    # this will happen when we have a self-referential class
    next if (
      $other_rel eq $rel
        and
      $self == $other_rsrc
    );

    # only consider stuff that points back to us
    # "us" here is tricky - if we are in a schema registration, we want
    # to use the source_names, otherwise we will use the actual classes

    my $roundtripped_rsrc;
    next unless (

      # the schema may be partially loaded
      $roundtripped_rsrc = dbic_internal_try { $other_rsrc->related_source($other_rel) }

        and

      (

        (
          $our_registered_source_name
            and
          (
            $our_registered_source_name
              eq
            $roundtripped_rsrc->source_name||''
          )
        )

          or

        (
          $our_result_class
            eq
          $roundtripped_rsrc->result_class
        )
      )

        and

      my $their_resolved_relcond = dbic_internal_try {
        $other_rsrc->resolve_relationship_condition(
          rel_name => $other_rel,

          # an API where these are optional would be too cumbersome,
          # instead always pass in some dummy values
          DUMMY_ALIASPAIR,
        )
      }
    );


    $ret->{$other_rel} = $other_rsrc->relationship_info($other_rel) if (

      $their_resolved_relcond->{identity_map_matches_condition}

        and

      keys %{ $our_resolved_relcond->{identity_map} }
        ==
      keys %{ $their_resolved_relcond->{identity_map} }

        and

      serialize( $our_resolved_relcond->{identity_map} )
        eq
      serialize( { reverse %{ $their_resolved_relcond->{identity_map} } } )

    );
  }

  return $ret;
}

# optionally takes either an arrayref of column names, or a hashref of already
# retrieved colinfos
# returns an arrayref of column names of the shortest unique constraint
# (matching some of the input if any), giving preference to the PK
sub _identifying_column_set {
  my ($self, $cols) = @_;

  my %unique = $self->unique_constraints;
  my $colinfos = ref $cols eq 'HASH' ? $cols : $self->columns_info($cols||());

  # always prefer the PK first, and then shortest constraints first
  USET:
  for my $set (delete $unique{primary}, sort { @$a <=> @$b } (values %unique) ) {
    next unless $set && @$set;

    for (@$set) {
      next USET unless ($colinfos->{$_} && !$colinfos->{$_}{is_nullable} );
    }

    # copy so we can mangle it at will
    return [ @$set ];
  }

  return undef;
}

sub _minimal_valueset_satisfying_constraint {
  my $self = shift;
  my $args = { ref $_[0] eq 'HASH' ? %{ $_[0] } : @_ };

  $args->{columns_info} ||= $self->columns_info;

  my $vals = extract_equality_conditions(
    $args->{values},
    ($args->{carp_on_nulls} ? 'consider_nulls' : undef ),
  );

  my $cols;
  for my $col ($self->unique_constraint_columns($args->{constraint_name}) ) {
    if( ! exists $vals->{$col} or ( $vals->{$col}||'' ) eq UNRESOLVABLE_CONDITION ) {
      $cols->{missing}{$col} = undef;
    }
    elsif( ! defined $vals->{$col} ) {
      $cols->{$args->{carp_on_nulls} ? 'undefined' : 'missing'}{$col} = undef;
    }
    else {
      # we need to inject back the '=' as extract_equality_conditions()
      # will strip it from literals and values alike, resulting in an invalid
      # condition in the end
      $cols->{present}{$col} = { '=' => $vals->{$col} };
    }

    $cols->{fc}{$col} = 1 if (
      ( ! $cols->{missing} or ! exists $cols->{missing}{$col} )
        and
      keys %{ $args->{columns_info}{$col}{_filter_info} || {} }
    );
  }

  $self->throw_exception( sprintf ( "Unable to satisfy requested constraint '%s', missing values for column(s): %s",
    $args->{constraint_name},
    join (', ', map { "'$_'" } sort keys %{$cols->{missing}} ),
  ) ) if $cols->{missing};

  $self->throw_exception( sprintf (
    "Unable to satisfy requested constraint '%s', FilterColumn values not usable for column(s): %s",
    $args->{constraint_name},
    join (', ', map { "'$_'" } sort keys %{$cols->{fc}}),
  )) if $cols->{fc};

  if (
    $cols->{undefined}
      and
    !$ENV{DBIC_NULLABLE_KEY_NOWARN}
  ) {
    carp_unique ( sprintf (
      "NULL/undef values supplied for requested unique constraint '%s' (NULL "
    . 'values in column(s): %s). This is almost certainly not what you wanted, '
    . 'though you can set DBIC_NULLABLE_KEY_NOWARN to disable this warning.',
      $args->{constraint_name},
      join (', ', map { "'$_'" } sort keys %{$cols->{undefined}}),
    ));
  }

  return { map { %{ $cols->{$_}||{} } } qw(present undefined) };
}

# Returns the {from} structure used to express JOIN conditions
sub _resolve_join {
  my ($self, $join, $alias, $seen, $jpath, $parent_force_left) = @_;

  # we need a supplied one, because we do in-place modifications, no returns
  $self->throw_exception ('You must supply a seen hashref as the 3rd argument to _resolve_join')
    unless ref $seen eq 'HASH';

  $self->throw_exception ('You must supply a joinpath arrayref as the 4th argument to _resolve_join')
    unless ref $jpath eq 'ARRAY';

  $jpath = [@$jpath]; # copy

  if (not defined $join or not length $join) {
    return ();
  }
  elsif (ref $join eq 'ARRAY') {
    return
      map {
        $self->_resolve_join($_, $alias, $seen, $jpath, $parent_force_left);
      } @$join;
  }
  elsif (ref $join eq 'HASH') {

    my @ret;
    for my $rel (keys %$join) {

      my $rel_info = $self->relationship_info($rel)
        or $self->throw_exception("No such relationship '$rel' on " . $self->source_name);

      my $force_left = $parent_force_left;
      $force_left ||= lc($rel_info->{attrs}{join_type}||'') eq 'left';

      # the actual seen value will be incremented by the recursion
      my $as = $self->schema->storage->relname_to_table_alias(
        $rel, ($seen->{$rel} && $seen->{$rel} + 1)
      );

      push @ret, (
        $self->_resolve_join($rel, $alias, $seen, [@$jpath], $force_left),
        $self->related_source($rel)->_resolve_join(
          $join->{$rel}, $as, $seen, [@$jpath, { $rel => $as }], $force_left
        )
      );
    }
    return @ret;

  }
  elsif (ref $join) {
    $self->throw_exception("No idea how to resolve join reftype ".ref $join);
  }
  else {
    my $count = ++$seen->{$join};
    my $as = $self->schema->storage->relname_to_table_alias(
      $join, ($count > 1 && $count)
    );

    my $rel_info = $self->relationship_info($join)
      or $self->throw_exception("No such relationship $join on " . $self->source_name);

    my $rel_src = $self->related_source($join);
    return [ { $as => $rel_src->from,
               -rsrc => $rel_src,
               -join_type => $parent_force_left
                  ? 'left'
                  : $rel_info->{attrs}{join_type}
                ,
               -join_path => [@$jpath, { $join => $as } ],
               -is_single => (
                  ! $rel_info->{attrs}{accessor}
                    or
                  $rel_info->{attrs}{accessor} eq 'single'
                    or
                  $rel_info->{attrs}{accessor} eq 'filter'
                ),
               -alias => $as,
               -relation_chain_depth => ( $seen->{-relation_chain_depth} || 0 ) + 1,
             },
             $self->resolve_relationship_condition(
               rel_name => $join,
               self_alias => $alias,
               foreign_alias => $as,
             )->{condition},
          ];
  }
}

sub pk_depends_on {
  carp 'pk_depends_on is a private method, stop calling it';
  my $self = shift;
  $self->_pk_depends_on (@_);
}

# Determines whether a relation is dependent on an object from this source
# having already been inserted. Takes the name of the relationship and a
# hashref of columns of the related object.
sub _pk_depends_on {
  my ($self, $rel_name, $rel_data) = @_;

  my $relinfo = $self->relationship_info($rel_name);

  # don't assume things if the relationship direction is specified
  return $relinfo->{attrs}{is_foreign_key_constraint}
    if exists ($relinfo->{attrs}{is_foreign_key_constraint});

  my $cond = $relinfo->{cond};
  return 0 unless ref($cond) eq 'HASH';

  # map { foreign.foo => 'self.bar' } to { bar => 'foo' }
  my $keyhash = { map { my $x = $_; $x =~ s/.*\.//; $x; } reverse %$cond };

  # assume anything that references our PK probably is dependent on us
  # rather than vice versa, unless the far side is (a) defined or (b)
  # auto-increment
  my $rel_source = $self->related_source($rel_name);

  my $colinfos;

  foreach my $p ($self->primary_columns) {
    return 0 if (
      exists $keyhash->{$p}
        and
      ! defined( $rel_data->{$keyhash->{$p}} )
        and
      ! ( $colinfos ||= $rel_source->columns_info )
         ->{$keyhash->{$p}}{is_auto_increment}
    )
  }

  return 1;
}

sub __strip_relcond :DBIC_method_is_indirect_sugar {
  DBIx::Class::Exception->throw(
    '__strip_relcond() has been removed with no replacement, '
  . 'ask for advice on IRC if this affected you'
  );
}

sub compare_relationship_keys :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  carp_unique( 'compare_relationship_keys() is deprecated, ask on IRC for a better alternative' );
  bag_eq( $_[1], $_[2] );
}

sub _compare_relationship_keys :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  carp_unique( '_compare_relationship_keys() is deprecated, ask on IRC for a better alternative' );
  bag_eq( $_[1], $_[2] );
}

sub _resolve_relationship_condition :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;

  # carp() - has been on CPAN for less than 2 years
  carp '_resolve_relationship_condition() is deprecated - see resolve_relationship_condition() instead';

  shift->resolve_relationship_condition(@_);
}

sub resolve_condition :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;

  # carp() - has been discouraged forever
  carp 'resolve_condition() is deprecated - see resolve_relationship_condition() instead';

  shift->_resolve_condition (@_);
}

sub _resolve_condition :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;

  # carp_unique() - the interface replacing it only became reality in Sep 2016
  carp_unique '_resolve_condition() is deprecated - see resolve_relationship_condition() instead';

#######################
### API Design? What's that...? (a backwards compatible shim, kill me now)

  my ($self, $cond, @res_args, $rel_name);

  # we *SIMPLY DON'T KNOW YET* which arg is which, yay
  ($self, $cond, $res_args[0], $res_args[1], $rel_name) = @_;

  # assume that an undef is an object-like unset (set_from_related(undef))
  my @is_objlike = map { ! defined $_ or length ref $_ } (@res_args);

  # turn objlike into proper objects for saner code further down
  for (0,1) {
    next unless $is_objlike[$_];

    if ( defined blessed $res_args[$_] ) {

      # but wait - there is more!!! WHAT THE FUCK?!?!?!?!
      if ($res_args[$_]->isa('DBIx::Class::ResultSet')) {
        carp('Passing a resultset for relationship resolution makes no sense - invoking __gremlins__');
        $is_objlike[$_] = 0;
        $res_args[$_] = '__gremlins__';
      }
      # more compat
      elsif( $_ == 0 and $res_args[0]->isa( $__expected_result_class_isa ) ) {
        my $fvals = { $res_args[0]->get_columns };

        # The very low level resolve_relationship_condition() deliberately contains
        # extra logic to ensure that it isn't passed garbage. Unfortunately we can
        # get into a situation where an object *has* extra columns on it, which
        # the interface of ->get_columns is obligated to return. In order not to
        # compromise the sanity checks within r_r_c, simply do a cleanup pass here,
        # and in 2 other spots within the codebase to keep things consistent
        #
        # FIXME - perhaps this should warn, but that's a battle for another day
        #
        $res_args[0] = { map {
          exists $fvals->{$_}
            ? ( $_ => $fvals->{$_} )
            : ()
        } $res_args[0]->result_source->columns };
      }
    }
    else {
      $res_args[$_] ||= {};

      # hate everywhere - have to pass in as a plain hash
      # pretending to be an object at least for now
      $self->throw_exception("Unsupported object-like structure encountered: $res_args[$_]")
        unless ref $res_args[$_] eq 'HASH';
    }
  }

  my $args = {
    # where-is-waldo block guesses relname, then further down we override it if available
    (
      $is_objlike[1] ? ( rel_name => $res_args[0], self_alias => $res_args[0], foreign_alias => 'me',         self_result_object  => $res_args[1] )
    : $is_objlike[0] ? ( rel_name => $res_args[1], self_alias => 'me',         foreign_alias => $res_args[1], foreign_values      => $res_args[0] )
    :                  ( rel_name => $res_args[0], self_alias => $res_args[1], foreign_alias => $res_args[0]                                      )
    ),

    ( $rel_name ? ( rel_name => $rel_name ) : () ),
  };

  # Allowing passing relconds different than the relationshup itself is cute,
  # but likely dangerous. Remove that from the API of resolve_relationship_condition,
  # and instead make it "hard on purpose"
  local $self->relationship_info( $args->{rel_name} )->{cond} = $cond if defined $cond;

#######################

  # now it's fucking easy isn't it?!
  my $rc = $self->resolve_relationship_condition( $args );

  my @res = (
    ( $rc->{join_free_condition} || $rc->{condition} ),
    ! $rc->{join_free_condition},
  );

  # resolve_relationship_condition always returns qualified cols even in the
  # case of join_free_condition, but nothing downstream expects this
  if ($rc->{join_free_condition} and ref $res[0] eq 'HASH') {
    $res[0] = { map
      { ($_ =~ /\.(.+)/) => $res[0]{$_} }
      keys %{$res[0]}
    };
  }

  # and more legacy
  return wantarray ? @res : $res[0];
}

# Keep this indefinitely. There is evidence of both CPAN and
# darkpan using it, and there isn't much harm in an extra var
# anyway.
our $UNRESOLVABLE_CONDITION = UNRESOLVABLE_CONDITION;
# YES I KNOW THIS IS EVIL
# it is there to save darkpan from themselves, since internally
# we are moving to a constant
Internals::SvREADONLY($UNRESOLVABLE_CONDITION => 1);

=head2 resolve_relationship_condition

NOTE: You generally B<SHOULD NOT> need to use this functionality... until you
do. The API description is terse on purpose. If the text below doesn't make
sense right away (based on the context which prompted you to look here) it is
almost certain you are reaching for the wrong tool. Please consider asking for
advice in any of the support channels before proceeding.

=over 4

=item Arguments: C<\%args> as shown below (C<B<*>> denotes mandatory args):

  * rel_name                    => $string

  * foreign_alias               => $string

  * self_alias                  => $string

    foreign_values              => \%column_value_pairs

    self_result_object          => $ResultObject

    require_join_free_condition => $bool ( results in exception on failure to construct a JF-cond )

    require_join_free_values    => $bool ( results in exception on failure to return an equality-only JF-cond )

=item Return Value: C<\%resolution_result> as shown below (C<B<*>> denotes always-resent parts of the result):

  * condition                      => $sqla_condition ( always present, valid, *likely* fully qualified, SQL::Abstract-compatible structure )

    identity_map                   => \%foreign_to_self_equailty_map ( list of declared-equal foreign/self *unqualified* column names )

    identity_map_matches_condition => $bool ( indicates whether the entire condition is expressed within the identity_map )

    join_free_condition            => \%sqla_condition_fully_resolvable_via_foreign_table
                                      ( always a hash, all keys guaranteed to be valid *fully qualified* columns )

    join_free_values               => \%unqalified_version_of_join_free_condition
                                      ( IFF the returned join_free_condition contains only exact values (no expressions), this would be
                                        a hashref identical to join_free_condition, except with all column names *unqualified* )

=back

This is the low-level method used to convert a declared relationship into
various parameters consumed by higher level functions. It is provided as a
stable official API, as the logic it encapsulates grew incredibly complex with
time. While calling this method directly B<is generally discouraged>, you
absolutely B<should be using it> in codepaths containing the moral equivalent
of:

  ...
  if( ref $some_rsrc->relationship_info($somerel)->{cond} eq 'HASH' ) {
    ...
  }
  ...

=cut

# TODO - expand the documentation above, too terse

sub resolve_relationship_condition {
  my $self = shift;

  my $args = { ref $_[0] eq 'HASH' ? %{ $_[0] } : @_ };

  for ( qw( rel_name self_alias foreign_alias ) ) {
    $self->throw_exception("Mandatory argument '$_' to resolve_relationship_condition() is not a plain string")
      if !defined $args->{$_} or length ref $args->{$_};
  }

  $self->throw_exception("Arguments 'self_alias' and 'foreign_alias' may not be identical")
    if $args->{self_alias} eq $args->{foreign_alias};

# TEMP
  my $exception_rel_id = "relationship '$args->{rel_name}' on source '@{[ $self->source_name || $self->result_class ]}'";

  my $rel_info = $self->relationship_info($args->{rel_name})
# TEMP
#    or $self->throw_exception( "No such $exception_rel_id" );
    or carp_unique("Requesting resolution on non-existent relationship '$args->{rel_name}' on source '@{[ $self->source_name ]}': fix your code *soon*, as it will break with the next major version");

# TEMP
  $exception_rel_id = "relationship '$rel_info->{_original_name}' on source '@{[ $self->source_name ]}'"
    if $rel_info and exists $rel_info->{_original_name};

  $self->throw_exception("No practical way to resolve $exception_rel_id between two data structures")
    if exists $args->{self_result_object} and exists $args->{foreign_values};

  $args->{require_join_free_condition} ||= !!$args->{require_join_free_values};

  $self->throw_exception( "Argument 'self_result_object' must be an object inheriting from '$__expected_result_class_isa'" )
    if (
      exists $args->{self_result_object}
        and
      (
        ! defined blessed $args->{self_result_object}
          or
        ! $args->{self_result_object}->isa( $__expected_result_class_isa )
      )
    )
  ;

  my $rel_rsrc = $self->related_source($args->{rel_name});

  if (
    exists $args->{foreign_values}
      and
    (
      ref $args->{foreign_values} eq 'HASH'
        or
      $self->throw_exception(
        "Argument 'foreign_values' must be a hash reference"
      )
    )
      and
    keys %{$args->{foreign_values}}
  ) {

    my ($col_idx, $rel_idx) = map
      { { map { $_ => 1 } $rel_rsrc->$_ } }
      qw( columns relationships )
    ;

    my $equivalencies;

    # re-build {foreign_values} excluding refs as follows
    # ( hot codepath: intentionally convoluted )
    #
    $args->{foreign_values} = { map {
      (
        $_ !~ /^-/
          or
        $self->throw_exception(
          "The key '$_' supplied as part of 'foreign_values' during "
         . 'relationship resolution must be a column name, not a function'
        )
      )
        and
      (
        # skip if relationship ( means a multicreate stub was passed in )
        # skip if literal ( can't infer anything about it )
        # or plain throw if nonequiv yet not literal
        (
          length ref $args->{foreign_values}{$_}
            and
          (
            $rel_idx->{$_}
              or
            is_literal_value($args->{foreign_values}{$_})
              or
            (
              (
                ! exists(
                  ( $equivalencies ||= extract_equality_conditions( $args->{foreign_values}, 'consider nulls' ) )
                    ->{$_}
                )
                  or
                ($equivalencies->{$_}||'') eq UNRESOLVABLE_CONDITION
              )
                and
              $self->throw_exception(
                "Resolution of relationship '$args->{rel_name}' failed: "
              . "supplied value for foreign column '$_' is not a direct "
              . 'equivalence expression'
              )
            )
          )
        )                             ? ()
      : $col_idx->{$_}                ? ( $_ => $args->{foreign_values}{$_} )
                                      : $self->throw_exception(
            "The key '$_' supplied as part of 'foreign_values' during "
           . 'relationship resolution is not a column on related source '
           . "'@{[ $rel_rsrc->source_name ]}'"
          )
      )
    } keys %{$args->{foreign_values}} };
  }

  my $ret;

  if (ref $rel_info->{cond} eq 'CODE') {

    my $cref_args = {
      rel_name => $args->{rel_name},
      self_resultsource => $self,
      self_alias => $args->{self_alias},
      foreign_alias => $args->{foreign_alias},
      ( map
        { (exists $args->{$_}) ? ( $_ => $args->{$_} ) : () }
        qw( self_result_object foreign_values )
      ),
    };

    # legacy - never remove these!!!
    $cref_args->{foreign_relname} = $cref_args->{rel_name};

    $cref_args->{self_rowobj} = $cref_args->{self_result_object}
      if exists $cref_args->{self_result_object};

    ($ret->{condition}, $ret->{join_free_condition}, my @extra) = $rel_info->{cond}->($cref_args);

    # sanity check
    $self->throw_exception("A custom condition coderef can return at most 2 conditions, but $exception_rel_id returned extra values: @extra")
      if @extra;

    if( $ret->{join_free_condition} ) {

      $self->throw_exception (
        "The join-free condition returned for $exception_rel_id must be a hash reference"
      ) unless ref $ret->{join_free_condition} eq 'HASH';

      my ($joinfree_alias, $joinfree_source);
      if (defined $args->{self_result_object}) {
        $joinfree_alias = $args->{foreign_alias};
        $joinfree_source = $rel_rsrc;
      }
      elsif (defined $args->{foreign_values}) {
        $joinfree_alias = $args->{self_alias};
        $joinfree_source = $self;
      }

      # FIXME sanity check until things stabilize, remove at some point
      $self->throw_exception (
        "A join-free condition returned for $exception_rel_id without a result object to chain from"
      ) unless $joinfree_alias;

      my $fq_col_list = { map
        { ( "$joinfree_alias.$_" => 1 ) }
        $joinfree_source->columns
      };

      exists $fq_col_list->{$_} or $self->throw_exception (
        "The join-free condition returned for $exception_rel_id may only "
      . 'contain keys that are fully qualified column names of the corresponding source '
      . "'$joinfree_alias' (instead it returned '$_')"
      ) for keys %{$ret->{join_free_condition}};

      (
        defined blessed($_)
          and
        $_->isa( $__expected_result_class_isa )
          and
        $self->throw_exception (
          "The join-free condition returned for $exception_rel_id may not "
        . 'contain result objects as values - perhaps instead of invoking '
        . '->$something you meant to return ->get_column($something)'
        )
      ) for values %{$ret->{join_free_condition}};

    }
  }
  elsif (ref $rel_info->{cond} eq 'HASH') {

    # the condition is static - use parallel arrays
    # for a "pivot" depending on which side of the
    # rel did we get as an object
    my (@f_cols, @l_cols);
    for my $fc (keys %{ $rel_info->{cond} }) {
      my $lc = $rel_info->{cond}{$fc};

      # FIXME STRICTMODE should probably check these are valid columns
      $fc =~ s/^foreign\.// ||
        $self->throw_exception("Invalid rel cond key '$fc'");

      $lc =~ s/^self\.// ||
        $self->throw_exception("Invalid rel cond val '$lc'");

      push @f_cols, $fc;
      push @l_cols, $lc;
    }

    # construct the crosstable condition and the identity map
    for  (0..$#f_cols) {
      $ret->{condition}{"$args->{foreign_alias}.$f_cols[$_]"} = { -ident => "$args->{self_alias}.$l_cols[$_]" };

      # explicit value stringification is deliberate - leave no room for
      # interpretation when comparing sets of keys
      $ret->{identity_map}{$l_cols[$_]} = "$f_cols[$_]";
    };

    if ($args->{foreign_values}) {
      $ret->{join_free_condition}{"$args->{self_alias}.$l_cols[$_]"}
        = $ret->{join_free_values}{$l_cols[$_]}
          = $args->{foreign_values}{$f_cols[$_]}
        for 0..$#f_cols;
    }
    elsif (defined $args->{self_result_object}) {

      # FIXME - compat block due to inconsistency of get_columns() vs has_column_loaded()
      # The former returns cached-in related single rels, while the latter is doing what
      # it says on the tin. Thus the more logical "get all columns and barf if something
      # is missing" is a non-starter, and we move through each column one by one :/

      $args->{self_result_object}->has_column_loaded( $l_cols[$_] )

            ? $ret->{join_free_condition}{"$args->{foreign_alias}.$f_cols[$_]"}
                = $ret->{join_free_values}{$f_cols[$_]}
                  = $args->{self_result_object}->get_column( $l_cols[$_] )

    : $args->{self_result_object}->in_storage

            ? $self->throw_exception(sprintf
                "Unable to resolve relationship '%s' from object '%s': column '%s' not "
              . 'loaded from storage (or not passed to new() prior to insert()). You '
            . 'probably need to call ->discard_changes to get the server-side defaults '
            . 'from the database',
              $args->{rel_name},
              $args->{self_result_object},
              $l_cols[$_],
            )

      # non-resolvable yet not in storage - give it a pass
      # FIXME - while this is what the code has done for ages, it doesn't seem right :(
            : (
              delete $ret->{join_free_condition},
              delete $ret->{join_free_values},
              last
            )

        for 0 .. $#l_cols;
    }
  }
  elsif (ref $rel_info->{cond} eq 'ARRAY') {
    if (@{ $rel_info->{cond} } == 0) {
      $ret = {
        condition => UNRESOLVABLE_CONDITION,
      };
    }
    else {
      my @subconds = map {
        local $rel_info->{cond} = $_;
        $self->resolve_relationship_condition( $args );
      } @{ $rel_info->{cond} };

      if( @{ $rel_info->{cond} } == 1 ) {
        $ret = $subconds[0];
      }
      else {
        for my $subcond ( @subconds ) {
          $self->throw_exception('Either all or none of the OR-condition members must resolve to a join-free condition')
            if ( $ret and ( $ret->{join_free_condition} xor $subcond->{join_free_condition} ) );

          # we are discarding join_free_values from individual 'OR' branches here
          # see @nonvalues checks below
          $subcond->{$_} and push @{$ret->{$_}}, $subcond->{$_} for (qw(condition join_free_condition));
        }
      }
    }
  }
  else {
    $self->throw_exception ("Can't handle condition $rel_info->{cond} for $exception_rel_id yet :(");
  }


  # Explicit normalization pass
  # ( nobody really knows what a CODE can return )
  # Explicitly leave U_C alone - it would be normalized
  # to an { -and => [ U_C ] }
  defined $ret->{$_}
    and
  $ret->{$_} ne UNRESOLVABLE_CONDITION
    and
  $ret->{$_} = normalize_sqla_condition($ret->{$_})
    for qw(condition join_free_condition);


  if (
    $args->{require_join_free_condition}
      and
    ! defined $ret->{join_free_condition}
  ) {
    $self->throw_exception(
      ucfirst sprintf "$exception_rel_id does not resolve to a %sjoin-free condition fragment",
        exists $args->{foreign_values}
          ? "'foreign_values'-based reversed-"
          : ''
    );
  }

  # we got something back (not from a static cond) - sanity check and infer values if we can
  # ( in case of a static cond join_free_values is already pre-populated for us )
  my @nonvalues;
  if(
    $ret->{join_free_condition}
      and
    ! $ret->{join_free_values}
  ) {

    my $jfc_eqs = extract_equality_conditions(
      $ret->{join_free_condition},
      'consider_nulls'
    );

    for( keys %{ $ret->{join_free_condition} } ) {
      if( $_ =~ /^-/ ) {
        push @nonvalues, { $_ => $ret->{join_free_condition}{$_} };
      }
      else {
        # a join_free_condition is fully qualified by definition
        my ($col) = $_ =~ /\.(.+)/ or carp_unique(
          'Internal error - extract_equality_conditions() returned a '
        . "non-fully-qualified key '$_'. *Please* file a bugreport "
        . "including your definition of $exception_rel_id"
        );

        if (exists $jfc_eqs->{$_} and ($jfc_eqs->{$_}||'') ne UNRESOLVABLE_CONDITION) {
          $ret->{join_free_values}{$col} = $jfc_eqs->{$_};
        }
        else {
          push @nonvalues, { $_ => $ret->{join_free_condition}{$_} };
        }
      }
    }

    # all or nothing
    delete $ret->{join_free_values} if @nonvalues;
  }


  # throw only if the user explicitly asked
  $args->{require_join_free_values}
    and
  @nonvalues
    and
  $self->throw_exception(
    "Unable to complete value inferrence - $exception_rel_id results in expression(s) instead of definitive values: "
  . do {
      # FIXME - used for diag only, but still icky
      my $sqlm =
        dbic_internal_try { $self->schema->storage->sql_maker }
          ||
        (
          require DBIx::Class::SQLMaker
            and
          DBIx::Class::SQLMaker->new
        )
      ;
      local $sqlm->{quote_char};
      local $sqlm->{_dequalify_idents} = 1;
      ($sqlm->_recurse_where({ -and => \@nonvalues }))[0]
    }
  );


  my $identity_map_incomplete;

  # add the identities based on the main condition
  # (may already be there, since easy to calculate on the fly in the HASH case)
  if ( ! $ret->{identity_map} ) {

    my $col_eqs = extract_equality_conditions($ret->{condition});

    $identity_map_incomplete++ if (
      $ret->{condition} eq UNRESOLVABLE_CONDITION
        or
      (
        keys %{$ret->{condition}}
          !=
        keys %$col_eqs
      )
    );

    my $colinfos;
    for my $lhs (keys %$col_eqs) {

      # start with the assumption it won't work
      $identity_map_incomplete++;

      next if $col_eqs->{$lhs} eq UNRESOLVABLE_CONDITION;

      # there is no way to know who is right and who is left in a cref
      # therefore a full blown resolution call, and figure out the
      # direction a bit further below
      $colinfos ||= fromspec_columns_info([
        { -alias => $args->{self_alias}, -rsrc => $self },
        { -alias => $args->{foreign_alias}, -rsrc => $rel_rsrc },
      ]);

      next unless $colinfos->{$lhs};  # someone is engaging in witchcraft

      if( my $rhs_ref =
        (
          ref $col_eqs->{$lhs} eq 'HASH'
            and
          keys %{$col_eqs->{$lhs}} == 1
            and
          exists $col_eqs->{$lhs}{-ident}
        )
          ? [ $col_eqs->{$lhs}{-ident} ]  # repack to match the RV of is_literal_value
          : is_literal_value( $col_eqs->{$lhs} )
      ) {
        if (
          $colinfos->{$rhs_ref->[0]}
            and
          $colinfos->{$lhs}{-source_alias} ne $colinfos->{$rhs_ref->[0]}{-source_alias}
        ) {
          ( $colinfos->{$lhs}{-source_alias} eq $args->{self_alias} )

            # explicit value stringification is deliberate - leave no room for
            # interpretation when comparing sets of keys
            ? ( $ret->{identity_map}{$colinfos->{$lhs}{-colname}} = "$colinfos->{$rhs_ref->[0]}{-colname}" )
            : ( $ret->{identity_map}{$colinfos->{$rhs_ref->[0]}{-colname}} = "$colinfos->{$lhs}{-colname}" )
          ;

          # well, what do you know!
          $identity_map_incomplete--;
        }
      }
      elsif (
        $col_eqs->{$lhs} =~ /^ ( \Q$args->{self_alias}\E \. .+ ) /x
          and
        ($colinfos->{$1}||{})->{-result_source} == $rel_rsrc
      ) {
        my ($lcol, $rcol) = map
          { $colinfos->{$_}{-colname} }
          ( $lhs, $1 )
        ;
        carp_unique(
          "The $exception_rel_id specifies equality of column '$lcol' and the "
        . "*VALUE* '$rcol' (you did not use the { -ident => ... } operator)"
        );
      }
    }
  }

  $ret->{identity_map_matches_condition} = ($identity_map_incomplete ? 0 : 1)
    if $ret->{identity_map};


  # cleanup before final return, easier to eyeball
  ! defined $ret->{$_} and delete $ret->{$_}
    for keys %$ret;


  # FIXME - temporary, to fool the idiotic check in SQLMaker::_join_condition
  $ret->{condition} = { -and => [ $ret->{condition} ] } unless (
    $ret->{condition} eq UNRESOLVABLE_CONDITION
      or
    (
      ref $ret->{condition} eq 'HASH'
        and
      grep { $_ =~ /^-/ } keys %{$ret->{condition}}
    )
  );


  if( DBIx::Class::_ENV_::ASSERT_NO_INCONSISTENT_RELATIONSHIP_RESOLUTION ) {

    my $sqlm =
      dbic_internal_try { $self->schema->storage->sql_maker }
        ||
      (
        require DBIx::Class::SQLMaker
          and
        DBIx::Class::SQLMaker->new
      )
    ;

    local $sqlm->{_dequalify_idents} = 1;

    my ( $cond_as_sql, $jf_cond_as_sql, $jf_vals_as_sql, $identmap_as_sql ) = map
      { join ' : ', map {
        ref $_ eq 'ARRAY' ? $_->[1]
      : defined $_        ? $_
                          : '{UNDEF}'
      } $sqlm->_recurse_where($_) }
      (
        ( map { $ret->{$_} } qw( condition join_free_condition join_free_values ) ),

        { map {
          # inverse because of how the idmap is declared
          $ret->{identity_map}{$_} => { -ident => $_ }
        } keys %{$ret->{identity_map}} },
      )
    ;


    emit_loud_diag(
      confess => 1,
      msg => sprintf (
        "Resolution of %s produced inconsistent metadata:\n\n"
      . "returned value of 'identity_map_matches_condition':    %s\n"
      . "returned 'condition' rendered as de-qualified SQL:     %s\n"
      . "returned 'identity_map' rendered as de-qualified SQL:  %s\n\n"
      . "The condition declared on the misclassified relationship is: %s ",
        $exception_rel_id,
        ( $ret->{identity_map_matches_condition} || 0 ),
        $cond_as_sql,
        $identmap_as_sql,
        dump_value( $rel_info->{cond} ),
      ),
    ) if (
      $ret->{identity_map_matches_condition}
        xor
      ( $cond_as_sql eq $identmap_as_sql )
    );


    emit_loud_diag(
      confess => 1,
      msg => sprintf (
        "Resolution of %s produced inconsistent metadata:\n\n"
      . "returned 'join_free_condition' rendered as de-qualified SQL: %s\n"
      . "returned 'join_free_values' rendered as de-qualified SQL:    %s\n\n"
      . "The condition declared on the misclassified relationship is: %s ",
        $exception_rel_id,
        $jf_cond_as_sql,
        $jf_vals_as_sql,
        dump_value( $rel_info->{cond} ),
      ),
    ) if (
      exists $ret->{join_free_condition}
        and
      (
        exists $ret->{join_free_values}
          xor
        ( $jf_cond_as_sql eq $jf_vals_as_sql )
      )
    );
  }

  $ret;
}

=head2 related_source

=over 4

=item Arguments: $rel_name

=item Return Value: $source

=back

Returns the result source object for the given relationship.

=cut

sub related_source {
  my ($self, $rel) = @_;
  if( !$self->has_relationship( $rel ) ) {
    $self->throw_exception("No such relationship '$rel' on " . $self->source_name);
  }

  # if we are not registered with a schema - just use the prototype
  # however if we do have a schema - ask for the source by name (and
  # throw in the process if all fails)
  if (my $schema = dbic_internal_try { $self->schema }) {
    $schema->source($self->relationship_info($rel)->{source});
  }
  else {
    my $class = $self->relationship_info($rel)->{class};
    $self->ensure_class_loaded($class);
    $class->result_source;
  }
}

=head2 related_class

=over 4

=item Arguments: $rel_name

=item Return Value: $classname

=back

Returns the class name for objects in the given relationship.

=cut

sub related_class {
  my ($self, $rel) = @_;
  if( !$self->has_relationship( $rel ) ) {
    $self->throw_exception("No such relationship '$rel' on " . $self->source_name);
  }
  return $self->schema->class($self->relationship_info($rel)->{source});
}

=head2 handle

=over 4

=item Arguments: none

=item Return Value: L<$source_handle|DBIx::Class::ResultSourceHandle>

=back

Obtain a new L<result source handle instance|DBIx::Class::ResultSourceHandle>
for this source. Used as a serializable pointer to this resultsource, as it is not
easy (nor advisable) to serialize CODErefs which may very well be present in e.g.
relationship definitions.

=cut

sub handle {
  require DBIx::Class::ResultSourceHandle;
  return DBIx::Class::ResultSourceHandle->new({
    source_moniker => $_[0]->source_name,

    # so that a detached thaw can be re-frozen
    $_[0]->{_detached_thaw}
      ? ( _detached_source  => $_[0]          )
      : ( schema            => $_[0]->schema  )
    ,
  });
}

my $global_phase_destroy;
sub DESTROY {
  ### NO detected_reinvoked_destructor check
  ### This code very much relies on being called multuple times

  return if $global_phase_destroy ||= in_global_destruction;

######
# !!! ACHTUNG !!!!
######
#
# Under no circumstances shall $_[0] be stored anywhere else (like copied to
# a lexical variable, or shifted, or anything else). Doing so will mess up
# the refcount of this particular result source, and will allow the $schema
# we are trying to save to reattach back to the source we are destroying.
# The relevant code checking refcounts is in ::Schema::DESTROY()

  # if we are not a schema instance holder - we don't matter
  return if(
    ! ref $_[0]->{schema}
      or
    isweak $_[0]->{schema}
  );

  # weaken our schema hold forcing the schema to find somewhere else to live
  # during global destruction (if we have not yet bailed out) this will throw
  # which will serve as a signal to not try doing anything else
  # however beware - on older perls the exception seems randomly untrappable
  # due to some weird race condition during thread joining :(((
  local $SIG{__DIE__} if $SIG{__DIE__};
  local $@ if DBIx::Class::_ENV_::UNSTABLE_DOLLARAT;
  eval {
    weaken $_[0]->{schema};

    # if schema is still there reintroduce ourselves with strong refs back to us
    if ($_[0]->{schema}) {
      my $srcregs = $_[0]->{schema}->source_registrations;

      defined $srcregs->{$_}
        and
      $srcregs->{$_} == $_[0]
        and
      $srcregs->{$_} = $_[0]
        and
      last
        for keys %$srcregs;
    }

    1;
  } or do {
    $global_phase_destroy = 1;
  };

  # Dummy NEXTSTATE ensuring the all temporaries on the stack are garbage
  # collected before leaving this scope. Depending on the code above, this
  # may very well be just a preventive measure guarding future modifications
  undef;
}

sub STORABLE_freeze { Storable::nfreeze($_[0]->handle) }

sub STORABLE_thaw {
  my ($self, $cloning, $ice) = @_;
  %$self = %{ (Storable::thaw($ice))->resolve };
}

=head2 throw_exception

See L<DBIx::Class::Schema/"throw_exception">.

=cut

sub throw_exception {
  my $self = shift;

  $self->{schema}
    ? $self->{schema}->throw_exception(@_)
    : DBIx::Class::Exception->throw(@_)
  ;
}

=head2 column_info_from_storage

=over

=item Arguments: 1/0 (default: 0)

=item Return Value: 1/0

=back

  __PACKAGE__->column_info_from_storage(1);

Enables the on-demand automatic loading of the above column
metadata from storage as necessary.  This is *deprecated*, and
should not be used.  It will be removed before 1.0.

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.

=cut

1;
