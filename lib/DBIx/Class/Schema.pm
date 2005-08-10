package DBIx::Class::Schema;

use strict;
use warnings;

use base qw/Class::Data::Inheritable/;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/Exception Componentised/);
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

  use base qw/DBIx::Class::Core/;

  __PACKAGE__->table('foo');
  ...

  in My/DB.pm

  use My::Schema;

  My::Schema->compose_connection('My::DB', $dsn, $user, $pass, $attrs);

  then in app code

  my @obj = My::DB::Foo->search({}); # My::DB::Foo isa My::Schema::Foo My::DB

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub register_class {
  my ($class, $name, $to_register) = @_;
  my %reg = %{$class->class_registrations};
  $reg{$name} = $to_register;
  $class->class_registrations(\%reg);
}

sub registered_classes {
  return values %{shift->class_registrations};
}

sub load_classes {
  my $class = shift;
  my @comp = grep { $_ !~ /^#/ } @_;
  unless (@comp) {
    eval "require Module::Find;";
    $class->throw("No arguments to load_classes and couldn't load".
      " Module::Find ($@)") if $@;
    @comp = map { substr $_, length "${class}::"  }
              Module::Find::findallmod($class);
  }
  foreach my $comp (@comp) {
    my $comp_class = "${class}::${comp}";
    eval "use $comp_class";
    die $@ if $@;
    $class->register_class($comp => $comp_class);
  }
}

sub compose_connection {
  my ($class, $target, @info) = @_;
  my $conn_class = "${target}::_db";
  $class->setup_connection_class($conn_class, @info);
  my %reg = %{ $class->class_registrations };
  my %target;
  my %map;
  while (my ($comp, $comp_class) = each %reg) {
    my $target_class = "${target}::${comp}";
    $class->inject_base($target_class, $conn_class, $comp_class);
    $target_class->table($comp_class->table);
    @map{$comp, $comp_class} = ($target_class, $target_class);
  }
  {
    no strict 'refs';
    *{"${target}::class"} =
      sub {
        my ($class, $to_map) = @_;
        return $map{$to_map};
      };
  }
  $conn_class->class_resolver($target);
}

sub setup_connection_class {
  my ($class, $target, @info) = @_;
  $class->inject_base($target => 'DBIx::Class');
  $target->load_components('DB');
  $target->connection(@info);
}

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

