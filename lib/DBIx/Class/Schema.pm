package DBIx::Class::Schema;

use strict;
use warnings;

use base qw/Class::Data::Inheritable/;
use DBIx::Class;

__PACKAGE__->mk_classdata('_class_registrations' => {});

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

  my @obj = My::DB::Foo->retrieve_all; # My::DB::Foo isa My::Schema::Foo My::DB

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub register_class {
  my ($class, $name, $to_register) = @_;
  my %reg = %{$class->_class_registrations};
  $reg{$name} = $to_register;
  $class->_class_registrations(\%reg);
}

sub load_classes {
  my $class = shift;
  my @comp = grep { $_ !~ /^#/ } @_;
  foreach my $comp (@comp) {
    my $comp_class = "${class}::${comp}";
    eval "use $comp_class";
    die $@ if $@;
    $class->register_class($comp => $comp_class);
  }
}

sub compose_connection {
  my ($class, $target, @info) = @_;
  $class->setup_connection_class($target, @info);
  my %reg = %{ $class->_class_registrations };
  while (my ($comp, $comp_class) = each %reg) {
    my $target_class = "${target}::${comp}";
    $class->inject_base($target_class, $comp_class, $target);
  }
}

sub setup_connection_class {
  my ($class, $target, @info) = @_;
  $class->inject_base($target => 'DBIx::Class');
  $target->load_components('DB');
  $target->connection(@info);
}

sub inject_base {
  my ($class, $target, @to_inject) = @_;
  {
    no strict 'refs';
    unshift(@{"${target}::ISA"}, @to_inject);
  }
}

1;

=back

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

