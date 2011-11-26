package DBIx::Class::ResultSource;

use strict;
use warnings;

use DBIx::Class::ResultSet;
use DBIx::Class::ResultSourceHandle;

use DBIx::Class::Exception;
use DBIx::Class::Carp;
use Try::Tiny;
use List::Util 'first';
use Scalar::Util qw/blessed weaken isweak/;
use namespace::clean;

use base qw/DBIx::Class/;

__PACKAGE__->mk_group_accessors(simple => qw/
  source_name name source_info
  _ordered_columns _columns _primaries _unique_constraints
  _relationships resultset_attributes
  column_info_from_storage
/);

__PACKAGE__->mk_group_accessors(component_class => qw/
  resultset_class
  result_class
/);

__PACKAGE__->mk_classdata( sqlt_deploy_callback => 'default_sqlt_deploy_hook' );

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
  __PACKAGE__->result_source_instance->is_virtual(1);
  __PACKAGE__->result_source_instance->view_definition(
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
L<DBIx::Class::ResultSoure::Table>. Luckily, to use tables as result
sources, you don't need to remember any of this.

Result sources representing select queries, or views, can also be
created, see L<DBIx::Class::ResultSource::View> for full details.

=head2 Finding result source objects

As mentioned above, a result source instance is created and stored for
you when you define a L<Result Class|DBIx::Class::Manual::Glossary/Result Class>.

You can retrieve the result source at runtime in the following ways:

=over

=item From a Schema object:

   $schema->source($source_name);

=item From a Row object:

   $row->result_source;

=item From a ResultSet object:

   $rs->result_source;

=back

=head1 METHODS

=pod

=cut

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;

  my $new = bless { %{$attrs || {}} }, $class;
  $new->{resultset_class} ||= 'DBIx::Class::ResultSet';
  $new->{resultset_attributes} = { %{$new->{resultset_attributes} || {}} };
  $new->{_ordered_columns} = [ @{$new->{_ordered_columns}||[]}];
  $new->{_columns} = { %{$new->{_columns}||{}} };
  $new->{_relationships} = { %{$new->{_relationships}||{}} };
  $new->{name} ||= "!!NAME NOT SET!!";
  $new->{_columns_info_loaded} ||= 0;
  return $new;
}

=pod

=head2 add_columns

=over

=item Arguments: @columns

=item Return value: The ResultSource object

=back

  $source->add_columns(qw/col1 col2 col3/);

  $source->add_columns('col1' => \%col1_info, 'col2' => \%col2_info, ...);

Adds columns to the result source. If supplied colname => hashref
pairs, uses the hashref as the L</column_info> for that column. Repeated
calls of this method will add more columns, not replace them.

The column names given will be created as accessor methods on your
L<DBIx::Class::Row> objects. You can change the name of the accessor
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

=item is_nullable

   { is_nullable => 1 }

Set this to a true value for a columns that is allowed to contain NULL
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

=item Return value: 1/0 (true/false)

=back

  $source->add_column('col' => \%info);

Add a single column and optional column info. Uses the same column
info keys as L</add_columns>.

=cut

sub add_columns {
  my ($self, @cols) = @_;
  $self->_ordered_columns(\@cols) unless $self->_ordered_columns;

  my @added;
  my $columns = $self->_columns;
  while (my $col = shift @cols) {
    my $column_info = {};
    if ($col =~ s/^\+//) {
      $column_info = $self->column_info($col);
    }

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
  return $self;
}

sub add_column { shift->add_columns(@_); } # DO NOT CHANGE THIS TO GLOB

=head2 has_column

=over

=item Arguments: $colname

=item Return value: 1/0 (true/false)

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

=item Return value: Hashref of info

=back

  my $info = $source->column_info($col);

Returns the column metadata hashref for a column, as originally passed
to L</add_columns>. See L</add_columns> above for information on the
contents of the hashref.

=cut

sub column_info {
  my ($self, $column) = @_;
  $self->throw_exception("No such column $column")
    unless exists $self->_columns->{$column};

  if ( ! $self->_columns->{$column}{data_type}
       and ! $self->{_columns_info_loaded}
       and $self->column_info_from_storage
       and my $stor = try { $self->storage } )
  {
    $self->{_columns_info_loaded}++;

    # try for the case of storage without table
    try {
      my $info = $stor->columns_info_for( $self->from );
      my $lc_info = { map
        { (lc $_) => $info->{$_} }
        ( keys %$info )
      };

      foreach my $col ( keys %{$self->_columns} ) {
        $self->_columns->{$col} = {
          %{ $self->_columns->{$col} },
          %{ $info->{$col} || $lc_info->{lc $col} || {} }
        };
      }
    };
  }

  return $self->_columns->{$column};
}

=head2 columns

=over

=item Arguments: None

=item Return value: Ordered list of column names

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

=item Return value: Hashref of column name/info pairs

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
    first { ! $_->{data_type} } values %$colinfo
      and
    ! $self->{_columns_info_loaded}
      and
    $self->column_info_from_storage
      and
    my $stor = try { $self->storage }
  ) {
    $self->{_columns_info_loaded}++;

    # try for the case of storage without table
    try {
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
          "No such column '%s' on source %s",
          $_,
          $self->source_name,
        ));
      }
    }
  }
  else {
    %ret = %$colinfo;
  }

  return \%ret;
}

=head2 remove_columns

=over

=item Arguments: @colnames

=item Return value: undefined

=back

  $source->remove_columns(qw/col1 col2 col3/);

Removes the given list of columns by name, from the result source.

B<Warning>: Removing a column that is also used in the sources primary
key, or in one of the sources unique constraints, B<will> result in a
broken result source.

=head2 remove_column

=over

=item Arguments: $colname

=item Return value: undefined

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

  my $columns = $self->_columns
    or return;

  my %to_remove;
  for (@to_remove) {
    delete $columns->{$_};
    ++$to_remove{$_};
  }

  $self->_ordered_columns([ grep { not $to_remove{$_} } @{$self->_ordered_columns} ]);
}

sub remove_column { shift->remove_columns(@_); } # DO NOT CHANGE THIS TO GLOB

=head2 set_primary_key

=over 4

=item Arguments: @cols

=item Return value: undefined

=back

Defines one or more columns as primary key for this source. Must be
called after L</add_columns>.

Additionally, defines a L<unique constraint|add_unique_constraint>
named C<primary>.

Note: you normally do want to define a primary key on your sources
B<even if the underlying database table does not have a primary key>.
See
L<DBIx::Class::Manual::Intro/The Significance and Importance of Primary Keys>
for more info.

=cut

sub set_primary_key {
  my ($self, @cols) = @_;
  # check if primary key columns are valid columns
  foreach my $col (@cols) {
    $self->throw_exception("No such column $col on table " . $self->name)
      unless $self->has_column($col);
  }
  $self->_primaries(\@cols);

  $self->add_unique_constraint(primary => \@cols);
}

=head2 primary_columns

=over 4

=item Arguments: None

=item Return value: Ordered list of primary column names

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
sub _pri_cols {
  my $self = shift;
  my @pcols = $self->primary_columns
    or $self->throw_exception (sprintf(
      "Operation requires a primary key to be declared on '%s' via set_primary_key",
      # source_name is set only after schema-registration
      $self->source_name || $self->result_class || $self->name || 'Unknown source...?',
    ));
  return @pcols;
}

=head2 sequence

Manually define the correct sequence for your table, to avoid the overhead
associated with looking up the sequence automatically. The supplied sequence
will be applied to the L</column_info> of each L<primary_key|/set_primary_key>

=over 4

=item Arguments: $sequence_name

=item Return value: undefined

=back

=cut

sub sequence {
  my ($self,$seq) = @_;

  my @pks = $self->primary_columns
    or return;

  $_->{sequence} = $seq
    for values %{ $self->columns_info (\@pks) };
}


=head2 add_unique_constraint

=over 4

=item Arguments: $name?, \@colnames

=item Return value: undefined

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

=item Return value: undefined

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

sub add_unique_constraints {
  my $self = shift;
  my @constraints = @_;

  if ( !(@constraints % 2) && first { ref $_ ne 'ARRAY' } @constraints ) {
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

=item Return value: Constraint name

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

  return join '_', $name, @$cols;
}

=head2 unique_constraints

=over 4

=item Arguments: None

=item Return value: Hash of unique constraint data

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

=item Arguments: None

=item Return value: Unique constraint names

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

=item Return value: List of constraint columns

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

=item Return value: $callback_name | \&callback_code

=back

  __PACKAGE__->sqlt_deploy_callback('mycallbackmethod');

   or

  __PACKAGE__->sqlt_deploy_callback(sub {
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

=head2 resultset

=over 4

=item Arguments: None

=item Return value: $resultset

=back

Returns a resultset for the given source. This will initially be created
on demand by calling

  $self->resultset_class->new($self, $self->resultset_attributes)

but is cached from then on unless resultset_class changes.

=head2 resultset_class

=over 4

=item Arguments: $classname

=item Return value: $classname

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

=item Arguments: \%attrs

=item Return value: \%attrs

=back

  # In the result class
  __PACKAGE__->resultset_attributes({ order_by => [ 'id' ] });

  # Or in code
  $source->resultset_attributes({ order_by => [ 'id' ] });

Store a collection of resultset attributes, that will be set on every
L<DBIx::Class::ResultSet> produced from this result source. For a full
list see L<DBIx::Class::ResultSet/ATTRIBUTES>.

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
      try { %{$self->schema->default_resultset_attributes} },
      %{$self->{resultset_attributes}},
    },
  );
}

=head2 name

=over 4

=item Arguments: None

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

=item Arguments: None

=item Return value: FROM clause

=back

  my $from_clause = $source->from();

Returns an expression of the source to be supplied to storage to specify
retrieval from this source. In the case of a database, the required FROM
clause contents.

=cut

sub from { die 'Virtual method!' }

=head2 schema

=over 4

=item Arguments: $schema

=item Return value: A schema object

=back

  my $schema = $source->schema();

Sets and/or returns the L<DBIx::Class::Schema> object to which this
result source instance has been attached to.

=cut

sub schema {
  if (@_ > 1) {
    $_[0]->{schema} = $_[1];
  }
  else {
    $_[0]->{schema} || do {
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

=item Arguments: None

=item Return value: A Storage object

=back

  $source->storage->debug(1);

Returns the storage handle for the current schema.

See also: L<DBIx::Class::Storage>

=cut

sub storage { shift->schema->storage; }

=head2 add_relationship

=over 4

=item Arguments: $relname, $related_source_name, \%cond, [ \%attrs ]

=item Return value: 1/true if it succeeded

=back

  $source->add_relationship('relname', 'related_source', $cond, $attrs);

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
  $self->throw_exception("Can't create relationship without join condition")
    unless $cond;
  $attrs ||= {};

  # Check foreign and self are right in cond
  if ( (ref $cond ||'') eq 'HASH') {
    for (keys %$cond) {
      $self->throw_exception("Keys of condition should be of form 'foreign.col', not '$_'")
        if /\./ && !/^foreign\./;
    }
  }

  my %rels = %{ $self->_relationships };
  $rels{$rel} = { class => $f_source_name,
                  source => $f_source_name,
                  cond  => $cond,
                  attrs => $attrs };
  $self->_relationships(\%rels);

  return $self;

# XXX disabled. doesn't work properly currently. skip in tests.

  my $f_source = $self->schema->source($f_source_name);
  unless ($f_source) {
    $self->ensure_class_loaded($f_source_name);
    $f_source = $f_source_name->result_source;
    #my $s_class = ref($self->schema);
    #$f_source_name =~ m/^${s_class}::(.*)$/;
    #$self->schema->register_class(($1 || $f_source_name), $f_source_name);
    #$f_source = $self->schema->source($f_source_name);
  }
  return unless $f_source; # Can't test rel without f_source

  try { $self->_resolve_join($rel, 'me', {}, []) }
  catch {
    # If the resolve failed, back out and re-throw the error
    delete $rels{$rel};
    $self->_relationships(\%rels);
    $self->throw_exception("Error creating relationship $rel: $_");
  };

  1;
}

=head2 relationships

=over 4

=item Arguments: None

=item Return value: List of relationship names

=back

  my @relnames = $source->relationships();

Returns all relationship names for this source.

=cut

sub relationships {
  return keys %{shift->_relationships};
}

=head2 relationship_info

=over 4

=item Arguments: $relname

=item Return value: Hashref of relation data,

=back

Returns a hash of relationship information for the specified relationship
name. The keys/values are as specified for L</add_relationship>.

=cut

sub relationship_info {
  my ($self, $rel) = @_;
  return $self->_relationships->{$rel};
}

=head2 has_relationship

=over 4

=item Arguments: $rel

=item Return value: 1/0 (true/false)

=back

Returns true if the source has a relationship of this name, false otherwise.

=cut

sub has_relationship {
  my ($self, $rel) = @_;
  return exists $self->_relationships->{$rel};
}

=head2 reverse_relationship_info

=over 4

=item Arguments: $relname

=item Return value: Hashref of relationship data

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

  my $rel_info = $self->relationship_info($rel)
    or $self->throw_exception("No such relationship '$rel'");

  my $ret = {};

  return $ret unless ((ref $rel_info->{cond}) eq 'HASH');

  my $stripped_cond = $self->__strip_relcond ($rel_info->{cond});

  my $rsrc_schema_moniker = $self->source_name
    if try { $self->schema };

  # this may be a partial schema or something else equally esoteric
  my $other_rsrc = try { $self->related_source($rel) }
    or return $ret;

  # Get all the relationships for that source that related to this source
  # whose foreign column set are our self columns on $rel and whose self
  # columns are our foreign columns on $rel
  foreach my $other_rel ($other_rsrc->relationships) {

    # only consider stuff that points back to us
    # "us" here is tricky - if we are in a schema registration, we want
    # to use the source_names, otherwise we will use the actual classes

    # the schema may be partial
    my $roundtrip_rsrc = try { $other_rsrc->related_source($other_rel) }
      or next;

    if ($rsrc_schema_moniker and try { $roundtrip_rsrc->schema } ) {
      next unless $rsrc_schema_moniker eq $roundtrip_rsrc->source_name;
    }
    else {
      next unless $self->result_class eq $roundtrip_rsrc->result_class;
    }

    my $other_rel_info = $other_rsrc->relationship_info($other_rel);

    # this can happen when we have a self-referential class
    next if $other_rel_info eq $rel_info;

    next unless ref $other_rel_info->{cond} eq 'HASH';
    my $other_stripped_cond = $self->__strip_relcond($other_rel_info->{cond});

    $ret->{$other_rel} = $other_rel_info if (
      $self->_compare_relationship_keys (
        [ keys %$stripped_cond ], [ values %$other_stripped_cond ]
      )
        and
      $self->_compare_relationship_keys (
        [ values %$stripped_cond ], [ keys %$other_stripped_cond ]
      )
    );
  }

  return $ret;
}

# all this does is removes the foreign/self prefix from a condition
sub __strip_relcond {
  +{
    map
      { map { /^ (?:foreign|self) \. (\w+) $/x } ($_, $_[1]{$_}) }
      keys %{$_[1]}
  }
}

sub compare_relationship_keys {
  carp 'compare_relationship_keys is a private method, stop calling it';
  my $self = shift;
  $self->_compare_relationship_keys (@_);
}

# Returns true if both sets of keynames are the same, false otherwise.
sub _compare_relationship_keys {
#  my ($self, $keys1, $keys2) = @_;
  return
    join ("\x00", sort @{$_[1]})
      eq
    join ("\x00", sort @{$_[2]})
  ;
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
      my $as = $self->storage->relname_to_table_alias(
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
    my $as = $self->storage->relname_to_table_alias(
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
                  $rel_info->{attrs}{accessor}
                    &&
                  first { $rel_info->{attrs}{accessor} eq $_ } (qw/single filter/)
                ),
               -alias => $as,
               -relation_chain_depth => $seen->{-relation_chain_depth} || 0,
             },
             scalar $self->_resolve_condition($rel_info->{cond}, $as, $alias, $join)
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
  my ($self, $relname, $rel_data) = @_;

  my $relinfo = $self->relationship_info($relname);

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
  my $rel_source = $self->related_source($relname);

  foreach my $p ($self->primary_columns) {
    if (exists $keyhash->{$p}) {
      unless (defined($rel_data->{$keyhash->{$p}})
              || $rel_source->column_info($keyhash->{$p})
                            ->{is_auto_increment}) {
        return 0;
      }
    }
  }

  return 1;
}

sub resolve_condition {
  carp 'resolve_condition is a private method, stop calling it';
  my $self = shift;
  $self->_resolve_condition (@_);
}

our $UNRESOLVABLE_CONDITION = \ '1 = 0';

# Resolves the passed condition to a concrete query fragment and a flag
# indicating whether this is a cross-table condition. Also an optional
# list of non-triviail values (notmally conditions) returned as a part
# of a joinfree condition hash
sub _resolve_condition {
  my ($self, $cond, $as, $for, $relname) = @_;

  my $obj_rel = !!blessed $for;

  if (ref $cond eq 'CODE') {
    my $relalias = $obj_rel ? 'me' : $as;

    my ($crosstable_cond, $joinfree_cond) = $cond->({
      self_alias => $obj_rel ? $as : $for,
      foreign_alias => $relalias,
      self_resultsource => $self,
      foreign_relname => $relname || ($obj_rel ? $as : $for),
      self_rowobj => $obj_rel ? $for : undef
    });

    my $cond_cols;
    if ($joinfree_cond) {

      # FIXME sanity check until things stabilize, remove at some point
      $self->throw_exception (
        "A join-free condition returned for relationship '$relname' without a row-object to chain from"
      ) unless $obj_rel;

      # FIXME another sanity check
      if (
        ref $joinfree_cond ne 'HASH'
          or
        first { $_ !~ /^\Q$relalias.\E.+/ } keys %$joinfree_cond
      ) {
        $self->throw_exception (
          "The join-free condition returned for relationship '$relname' must be a hash "
         .'reference with all keys being valid columns on the related result source'
        );
      }

      # normalize
      for (values %$joinfree_cond) {
        $_ = $_->{'='} if (
          ref $_ eq 'HASH'
            and
          keys %$_ == 1
            and
          exists $_->{'='}
        );
      }

      # see which parts of the joinfree cond are conditionals
      my $relcol_list = { map { $_ => 1 } $self->related_source($relname)->columns };

      for my $c (keys %$joinfree_cond) {
        my ($colname) = $c =~ /^ (?: \Q$relalias.\E )? (.+)/x;

        unless ($relcol_list->{$colname}) {
          push @$cond_cols, $colname;
          next;
        }

        if (
          ref $joinfree_cond->{$c}
            and
          ref $joinfree_cond->{$c} ne 'SCALAR'
            and
          ref $joinfree_cond->{$c} ne 'REF'
        ) {
          push @$cond_cols, $colname;
          next;
        }
      }

      return wantarray ? ($joinfree_cond, 0, $cond_cols) : $joinfree_cond;
    }
    else {
      return wantarray ? ($crosstable_cond, 1) : $crosstable_cond;
    }
  }
  elsif (ref $cond eq 'HASH') {
    my %ret;
    foreach my $k (keys %{$cond}) {
      my $v = $cond->{$k};
      # XXX should probably check these are valid columns
      $k =~ s/^foreign\.// ||
        $self->throw_exception("Invalid rel cond key ${k}");
      $v =~ s/^self\.// ||
        $self->throw_exception("Invalid rel cond val ${v}");
      if (ref $for) { # Object
        #warn "$self $k $for $v";
        unless ($for->has_column_loaded($v)) {
          if ($for->in_storage) {
            $self->throw_exception(sprintf
              "Unable to resolve relationship '%s' from object %s: column '%s' not "
            . 'loaded from storage (or not passed to new() prior to insert()). You '
            . 'probably need to call ->discard_changes to get the server-side defaults '
            . 'from the database.',
              $as,
              $for,
              $v,
            );
          }
          return $UNRESOLVABLE_CONDITION;
        }
        $ret{$k} = $for->get_column($v);
        #$ret{$k} = $for->get_column($v) if $for->has_column_loaded($v);
        #warn %ret;
      } elsif (!defined $for) { # undef, i.e. "no object"
        $ret{$k} = undef;
      } elsif (ref $as eq 'HASH') { # reverse hashref
        $ret{$v} = $as->{$k};
      } elsif (ref $as) { # reverse object
        $ret{$v} = $as->get_column($k);
      } elsif (!defined $as) { # undef, i.e. "no reverse object"
        $ret{$v} = undef;
      } else {
        $ret{"${as}.${k}"} = { -ident => "${for}.${v}" };
      }
    }

    return wantarray
      ? ( \%ret, ($obj_rel || !defined $as || ref $as) ? 0 : 1 )
      : \%ret
    ;
  }
  elsif (ref $cond eq 'ARRAY') {
    my (@ret, $crosstable);
    for (@$cond) {
      my ($cond, $crosstab) = $self->_resolve_condition($_, $as, $for, $relname);
      push @ret, $cond;
      $crosstable ||= $crosstab;
    }
    return wantarray ? (\@ret, $crosstable) : \@ret;
  }
  else {
    $self->throw_exception ("Can't handle condition $cond for relationship '$relname' yet :(");
  }
}

# Accepts one or more relationships for the current source and returns an
# array of column names for each of those relationships. Column names are
# prefixed relative to the current source, in accordance with where they appear
# in the supplied relationships.

sub _resolve_prefetch {
  my ($self, $pre, $alias, $alias_map, $order, $collapse, $pref_path) = @_;
  $pref_path ||= [];

  if (not defined $pre or not length $pre) {
    return ();
  }
  elsif( ref $pre eq 'ARRAY' ) {
    return
      map { $self->_resolve_prefetch( $_, $alias, $alias_map, $order, $collapse, [ @$pref_path ] ) }
        @$pre;
  }
  elsif( ref $pre eq 'HASH' ) {
    my @ret =
    map {
      $self->_resolve_prefetch($_, $alias, $alias_map, $order, $collapse, [ @$pref_path ] ),
      $self->related_source($_)->_resolve_prefetch(
               $pre->{$_}, "${alias}.$_", $alias_map, $order, $collapse, [ @$pref_path, $_] )
    } keys %$pre;
    return @ret;
  }
  elsif( ref $pre ) {
    $self->throw_exception(
      "don't know how to resolve prefetch reftype ".ref($pre));
  }
  else {
    my $p = $alias_map;
    $p = $p->{$_} for (@$pref_path, $pre);

    $self->throw_exception (
      "Unable to resolve prefetch '$pre' - join alias map does not contain an entry for path: "
      . join (' -> ', @$pref_path, $pre)
    ) if (ref $p->{-join_aliases} ne 'ARRAY' or not @{$p->{-join_aliases}} );

    my $as = shift @{$p->{-join_aliases}};

    my $rel_info = $self->relationship_info( $pre );
    $self->throw_exception( $self->source_name . " has no such relationship '$pre'" )
      unless $rel_info;
    my $as_prefix = ($alias =~ /^.*?\.(.+)$/ ? $1.'.' : '');
    my $rel_source = $self->related_source($pre);

    if ($rel_info->{attrs}{accessor} && $rel_info->{attrs}{accessor} eq 'multi') {
      $self->throw_exception(
        "Can't prefetch has_many ${pre} (join cond too complex)")
        unless ref($rel_info->{cond}) eq 'HASH';
      my $dots = @{[$as_prefix =~ m/\./g]} + 1; # +1 to match the ".${as_prefix}"

      if (my ($fail) = grep { @{[$_ =~ m/\./g]} == $dots }
                         keys %{$collapse}) {
        my ($last) = ($fail =~ /([^\.]+)$/);
        carp (
          "Prefetching multiple has_many rels ${last} and ${pre} "
          .(length($as_prefix)
            ? "at the same level (${as_prefix}) "
            : "at top level "
          )
          . 'will explode the number of row objects retrievable via ->next or ->all. '
          . 'Use at your own risk.'
        );
      }

      #my @col = map { (/^self\.(.+)$/ ? ("${as_prefix}.$1") : ()); }
      #              values %{$rel_info->{cond}};
      $collapse->{".${as_prefix}${pre}"} = [ $rel_source->_pri_cols ];
        # action at a distance. prepending the '.' allows simpler code
        # in ResultSet->_collapse_result
      my @key = map { (/^foreign\.(.+)$/ ? ($1) : ()); }
                    keys %{$rel_info->{cond}};
      push @$order, map { "${as}.$_" } @key;

      if (my $rel_order = $rel_info->{attrs}{order_by}) {
        # this is kludgy and incomplete, I am well aware
        # but the parent method is going away entirely anyway
        # so sod it
        my $sql_maker = $self->storage->sql_maker;
        my ($orig_ql, $orig_qr) = $sql_maker->_quote_chars;
        my $sep = $sql_maker->name_sep;

        # install our own quoter, so we can catch unqualified stuff
        local $sql_maker->{quote_char} = ["\x00", "\xFF"];

        my $quoted_prefix = "\x00${as}\xFF";

        for my $chunk ( $sql_maker->_order_by_chunks ($rel_order) ) {
          my @bind;
          ($chunk, @bind) = @$chunk if ref $chunk;

          $chunk = "${quoted_prefix}${sep}${chunk}"
            unless $chunk =~ /\Q$sep/;

          $chunk =~ s/\x00/$orig_ql/g;
          $chunk =~ s/\xFF/$orig_qr/g;
          push @$order, \[$chunk, @bind];
        }
      }
    }

    return map { [ "${as}.$_", "${as_prefix}${pre}.$_", ] }
      $rel_source->columns;
  }
}

=head2 related_source

=over 4

=item Arguments: $relname

=item Return value: $source

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
  if (my $schema = try { $self->schema }) {
    $schema->source($self->relationship_info($rel)->{source});
  }
  else {
    my $class = $self->relationship_info($rel)->{class};
    $self->ensure_class_loaded($class);
    $class->result_source_instance;
  }
}

=head2 related_class

=over 4

=item Arguments: $relname

=item Return value: $classname

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

=item Arguments: None

=item Return value: $source_handle

=back

Obtain a new L<result source handle instance|DBIx::Class::ResultSourceHandle>
for this source. Used as a serializable pointer to this resultsource, as it is not
easy (nor advisable) to serialize CODErefs which may very well be present in e.g.
relationship definitions.

=cut

sub handle {
  return DBIx::Class::ResultSourceHandle->new({
    source_moniker => $_[0]->source_name,

    # so that a detached thaw can be re-frozen
    $_[0]->{_detached_thaw}
      ? ( _detached_source  => $_[0]          )
      : ( schema            => $_[0]->schema  )
    ,
  });
}

{
  my $global_phase_destroy;

  # SpeedyCGI runs END blocks every cycle but keeps object instances
  # hence we have to disable the globaldestroy hatch, and rely on the
  # eval trap below (which appears to work, but is risky done so late)
  END { $global_phase_destroy = 1 unless $CGI::SpeedyCGI::i_am_speedy }

  sub DESTROY {
    return if $global_phase_destroy;

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
    local $@;
    eval {
      weaken $_[0]->{schema};
      1;
    } or do {
      $global_phase_destroy = 1;
      return;
    };


    # if schema is still there reintroduce ourselves with strong refs back to us
    if ($_[0]->{schema}) {
      my $srcregs = $_[0]->{schema}->source_registrations;
      for (keys %$srcregs) {
        next unless $srcregs->{$_};
        $srcregs->{$_} = $_[0] if $srcregs->{$_} == $_[0];
      }
    }
  }
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

=head2 source_info

Stores a hashref of per-source metadata.  No specific key names
have yet been standardized, the examples below are purely hypothetical
and don't actually accomplish anything on their own:

  __PACKAGE__->source_info({
    "_tablespace" => 'fast_disk_array_3',
    "_engine" => 'InnoDB',
  });

=head2 new

  $class->new();

  $class->new({attribute_name => value});

Creates a new ResultSource object.  Not normally called directly by end users.

=head2 column_info_from_storage

=over

=item Arguments: 1/0 (default: 0)

=item Return value: 1/0

=back

  __PACKAGE__->column_info_from_storage(1);

Enables the on-demand automatic loading of the above column
metadata from storage as necessary.  This is *deprecated*, and
should not be used.  It will be removed before 1.0.


=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
