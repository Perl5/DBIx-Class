package DBIx::Class::Schema;

use strict;
use warnings;

use Carp::Clan qw/^DBIx::Class/;
use UNIVERSAL::require;

use base qw/DBIx::Class/;

__PACKAGE__->mk_classdata('class_mappings' => {});
__PACKAGE__->mk_classdata('source_registrations' => {});
__PACKAGE__->mk_classdata('storage_type' => '::DBI');
__PACKAGE__->mk_classdata('storage');

=head1 NAME

DBIx::Class::Schema - composable schemas

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema/;
  
  # load My::Schema::Foo, My::Schema::Bar, My::Schema::Baz
  __PACKAGE__->load_classes(qw/Foo Bar Baz/);

  package My::Schema::Foo;
  use base qw/DBIx::Class/;
  __PACKAGE__->load_components(qw/PK::Auto::Pg Core/); # for example
  __PACKAGE__->table('foo');

  my $schema1 = My::Schema->connect(
    $dsn,
    $user,
    $password,
    $attrs
  );

  my $schema2 = My::Schema->connect( ... );

  # fetch objects using My::Schema::Foo
  my $resultset = $schema1->resultset('Foo')->search( ... );
  my @objects = $schema2->resultset('Foo')->search( ... );

=head1 DESCRIPTION

Creates database classes based on a schema. This is the recommended way to
use L<DBIx::Class> and allows you to use more than one concurrent connection
with your classes.

NB: If you're used to L<Class::DBI> it's worth reading the L</SYNOPSIS>
carefully as DBIx::Class does things a little differently. Note in
particular which module inherits off which.

=head1 METHODS

=head2 register_class <moniker> <component_class>

Registers a class which isa ResultSourceProxy; equivalent to calling

  $schema->register_source($moniker, $class->result_source_instance);

=cut

sub register_class {
  my ($self, $moniker, $to_register) = @_;
  $self->register_source($moniker => $to_register->result_source_instance);
}

=head2 register_source <moniker> <result source>

Registers the result source in the schema with the given moniker

=cut

sub register_source {
  my ($self, $moniker, $source) = @_;
  my %reg = %{$self->source_registrations};
  $reg{$moniker} = $source;
  $self->source_registrations(\%reg);
  $source->schema($self);
  if ($source->result_class) {
    my %map = %{$self->class_mappings};
    $map{$source->result_class} = $moniker;
    $self->class_mappings(\%map);
  }
} 

=head2 class

  my $class = $schema->class('Foo');

Retrieves the result class name for a given result source

=cut

sub class {
  my ($self, $moniker) = @_;
  return $self->source($moniker)->result_class;
}

=head2 source

  my $source = $schema->source('Foo');

Returns the result source object for the registered name

=cut

sub source {
  my ($self, $moniker) = @_;
  my $sreg = $self->source_registrations;
  return $sreg->{$moniker} if exists $sreg->{$moniker};

  # if we got here, they probably passed a full class name
  my $mapped = $self->class_mappings->{$moniker};
  $self->throw_exception("Can't find source for ${moniker}")
    unless $mapped && exists $sreg->{$mapped};
  return $sreg->{$mapped};
}

=head2 sources

  my @source_monikers = $schema->sources;

Returns the source monikers of all source registrations on this schema

=cut

sub sources { return keys %{shift->source_registrations}; }

=head2 resultset

  my $rs = $schema->resultset('Foo');

Returns the resultset for the registered moniker

=cut

sub resultset {
  my ($self, $moniker) = @_;
  return $self->source($moniker)->resultset;
}

=head2  load_classes [<classes>, (<class>, <class>), {<namespace> => [<classes>]}]

Uses L<Module::Find> to find all classes under the database class' namespace,
or uses the classes you select.  Then it loads the component (using L<use>), 
and registers them (using B<register_class>);

It is possible to comment out classes with a leading '#', but note that perl
will think it's a mistake (trying to use a comment in a qw list) so you'll
need to add "no warnings 'qw';" before your load_classes call.

=cut

sub load_classes {
  my ($class, @params) = @_;
  
  my %comps_for;
  
  if (@params) {
    foreach my $param (@params) {
      if (ref $param eq 'ARRAY') {
        # filter out commented entries
        my @modules = grep { $_ !~ /^#/ } @$param;
        
        push (@{$comps_for{$class}}, @modules);
      }
      elsif (ref $param eq 'HASH') {
        # more than one namespace possible
        for my $comp ( keys %$param ) {
          # filter out commented entries
          my @modules = grep { $_ !~ /^#/ } @{$param->{$comp}};

          push (@{$comps_for{$comp}}, @modules);
        }
      }
      else {
        # filter out commented entries
        push (@{$comps_for{$class}}, $param) if $param !~ /^#/;
      }
    }
  } else {
    eval "require Module::Find;";
    $class->throw_exception("No arguments to load_classes and couldn't load".
      " Module::Find ($@)") if $@;
    my @comp = map { substr $_, length "${class}::"  } Module::Find::findallmod($class);
    $comps_for{$class} = \@comp;
  }

  foreach my $prefix (keys %comps_for) {
    foreach my $comp (@{$comps_for{$prefix}||[]}) {
      my $comp_class = "${prefix}::${comp}";
      eval "use $comp_class"; # If it fails, assume the user fixed it
      if ($@) {
        die $@ unless $@ =~ /Can't locate/;
      }
      $class->register_class($comp => $comp_class);
      #  if $class->can('result_source_instance');
    }
  }
}

=head2 compose_connection <target> <@db_info>

This is the most important method in this class. it takes a target namespace,
as well as dbh connection info, and creates a L<DBIx::Class::DB> class as
well as subclasses for each of your database classes in this namespace, using
this connection.

It will also setup a ->class method on the target class, which lets you
resolve database classes based on the schema component name, for example

  MyApp::DB->class('Foo') # returns MyApp::DB::Foo, 
                          # which ISA MyApp::Schema::Foo

This is the recommended API for accessing Schema generated classes, and 
using it might give you instant advantages with future versions of DBIC.

WARNING: Loading components into Schema classes after compose_connection
may not cause them to be seen by the classes in your target namespace due
to the dispatch table approach used by Class::C3. If you do this you may find
you need to call Class::C3->reinitialize() afterwards to get the behaviour
you expect.

=cut

sub compose_connection {
  my ($self, $target, @info) = @_;
  my $base = 'DBIx::Class::ResultSetProxy';
  $base->require;

  if ($self eq $target) {
    # Pathological case, largely caused by the docs on early C::M::DBIC::Plain
    foreach my $moniker ($self->sources) {
      my $source = $self->source($moniker);
      my $class = $source->result_class;
      $self->inject_base($class, $base);
      $class->mk_classdata(resultset_instance => $source->resultset);
      $class->mk_classdata(class_resolver => $self);
    }
    $self->connection(@info);
    return $self;
  }

  my $schema = $self->compose_namespace($target, $base);
  $schema->connection(@info);
  foreach my $moniker ($schema->sources) {
    my $source = $schema->source($moniker);
    my $class = $source->result_class;
    #warn "$moniker $class $source ".$source->storage;
    $class->mk_classdata(result_source_instance => $source);
    $class->mk_classdata(resultset_instance => $source->resultset);
    $class->mk_classdata(class_resolver => $schema);
  }
  return $schema;
}

sub compose_namespace {
  my ($self, $target, $base) = @_;
  my %reg = %{ $self->source_registrations };
  my %target;
  my %map;
  my $schema = $self->clone;
  foreach my $moniker ($schema->sources) {
    my $source = $schema->source($moniker);
    my $target_class = "${target}::${moniker}";
    $self->inject_base(
      $target_class => $source->result_class, ($base ? $base : ())
    );
    $source->result_class($target_class);
  }
  {
    no strict 'refs';
    *{"${target}::schema"} =
      sub { $schema };
    foreach my $meth (qw/class source resultset/) {
      *{"${target}::${meth}"} =
        sub { shift->schema->$meth(@_) };
    }
  }
  return $schema;
}

=head2 setup_connection_class <$target> <@info>

Sets up a database connection class to inject between the schema
and the subclasses the schema creates.

=cut

sub setup_connection_class {
  my ($class, $target, @info) = @_;
  $class->inject_base($target => 'DBIx::Class::DB');
  #$target->load_components('DB');
  $target->connection(@info);
}

=head2 connection(@args)

Instantiates a new Storage object of type storage_type and passes the
arguments to $storage->connect_info. Sets the connection in-place on
the schema.

=cut

sub connection {
  my ($self, @info) = @_;
  my $storage_class = $self->storage_type;
  $storage_class = 'DBIx::Class::Storage'.$storage_class
    if $storage_class =~ m/^::/;
  $storage_class->require;
  my $storage = $storage_class->new;
  $storage->connect_info(\@info);
  $self->storage($storage);
  return $self;
}

=head2 connect(@info)

Conveneience method, equivalent to $schema->clone->connection(@info)

=cut

sub connect { shift->clone->connection(@_) };

=head2 clone

Clones the schema and its associated result_source objects and returns the
copy.

=cut

sub clone {
  my ($self) = @_;
  my $clone = bless({ (ref $self ? %$self : ()) }, ref $self || $self);
  foreach my $moniker ($self->sources) {
    my $source = $self->source($moniker);
    my $new = $source->new($source);
    $clone->register_source($moniker => $new);
  }
  return $clone;
}

=item populate($moniker, \@data);

Populates the source registered with the given moniker with the supplied data.
@data should be a list of listrefs, the first containing column names, the
second matching values - i.e.

$schema->populate('Foo', [
  [ qw/foo_id foo_string/ ],
  [ 1, 'One' ],
  [ 2, 'Two' ],
  ...
]);

=cut

sub populate {
  my ($self, $name, $data) = @_;
  my $rs = $self->resultset($name);
  my @names = @{shift(@$data)};
  foreach my $item (@$data) {
    my %create;
    @create{@names} = @$item;
    $rs->create(\%create);
  }
}

=item throw_exception

Defaults to using Carp::Clan to report errors from user perspective.

=cut

sub throw_exception {
  my ($self) = shift;
  croak @_;
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

