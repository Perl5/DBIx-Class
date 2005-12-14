package DBIx::Class::Schema;

use strict;
use warnings;
use DBIx::Class::DB;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/Exception/);
__PACKAGE__->mk_classdata('class_registrations' => {});

=head1 NAME

DBIx::Class::Schema - composable schemas

=head1 SYNOPSIS

in My/Schema.pm

  package My::Schema;

  use base qw/DBIx::Class::Schema/;

  __PACKAGE__->load_classes(qw/Foo Bar Baz/);

in My/Schema/Foo.pm

  package My::Schema::Foo;

  use base qw/DBIx::Class/;

  __PACKAGE__->load_components(qw/Core PK::Auto::Pg/); # for example
  __PACKAGE__->table('foo');
  ...

in My/DB.pm

  use My::Schema;

  My::Schema->compose_connection('My::DB', $dsn, $user, $pass, $attrs);

then in app code

  my @obj = My::DB::Foo->search({}); # My::DB::Foo isa My::Schema::Foo My::DB

=head1 DESCRIPTION

Creates database classes based on a schema. This allows you to have more than
one concurrent connection using the same database classes, by making 
subclasses under a new namespace for each connection. If you only need one 
class, you should probably use L<DBIx::Class::DB> directly instead.

NB: If you're used to L<Class::DBI> it's worth reading the L</SYNOPSIS>
carefully as DBIx::Class does things a little differently. Note in
particular which module inherits off which.

=head1 METHODS

=head2 register_class <component> <component_class>

Registers the class in the schema's class_registrations. This is a hash
containing database classes, keyed by their monikers. It's used by
compose_connection to create/modify all the existing database classes.

=cut

sub register_class {
  my ($class, $name, $to_register) = @_;
  my %reg = %{$class->class_registrations};
  $reg{$name} = $to_register;
  $class->class_registrations(\%reg);
}

=head2 registered_classes

Simple read-only accessor for the schema's registered classes. See 
register_class above if you want to modify it.


=cut

sub registered_classes {
  return values %{shift->class_registrations};
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
    $class->throw("No arguments to load_classes and couldn't load".
      " Module::Find ($@)") if $@;
    my @comp = map { substr $_, length "${class}::"  } Module::Find::findallmod($class);
    $comps_for{$class} = \@comp;
  }

  foreach my $prefix (keys %comps_for) {
    foreach my $comp (@{$comps_for{$prefix}||[]}) {
      my $comp_class = "${prefix}::${comp}";
      eval "use $comp_class"; # If it fails, assume the user fixed it
      $class->register_class($comp => $comp_class);
    }
  }
}

=head2 compose_connection <target> <@db_info>

This is the most important method in this class. it takes a target namespace,
as well as dbh connection info, and creates a L<DBIx::Class::DB> class as
well as subclasses for each of your database classes in this namespace, using
this connection.

It will also setup a ->table method on the target class, which lets you
resolve database classes based on the schema component name, for example

  MyApp::DB->table('Foo') # returns MyApp::DB::Foo, 
                          # which ISA MyApp::Schema::Foo

This is the recommended API for accessing Schema generated classes, and 
using it might give you instant advantages with future versions of DBIC.

=cut

sub compose_connection {
  my ($class, $target, @info) = @_;
  my $conn_class = "${target}::_db";
  $class->setup_connection_class($conn_class, @info);
  my %reg = %{ $class->class_registrations };
  my %target;
  my %map;
  while (my ($comp, $comp_class) = each %reg) {
    my $target_class = "${target}::${comp}";
    $class->inject_base($target_class, $comp_class, $conn_class);
    my $table = $comp_class->table->new({ %{$comp_class->table} });
    $table->result_class($target_class);
    $target_class->table($table);
    @map{$comp, $comp_class} = ($target_class, $target_class);
  }
  {
    no strict 'refs';
    *{"${target}::class"} =
      sub {
        my ($class, $to_map) = @_;
        return $map{$to_map};
      };
    *{"${target}::classes"} = sub { return \%map; };
  }
  $conn_class->class_resolver($target);
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

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

