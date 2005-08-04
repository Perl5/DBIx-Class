package DBIx::Class::Schema;

use strict;
use warnings;

use base qw/Class::Data::Inheritable/;
use DBIx::Class;

__PACKAGE__->mk_classdata('_class_registrations' => {});

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
  {
    no strict 'refs';
    unshift(@{"${target}::ISA"}, 'DBIx::Class');
  }
  $target->load_components('DB');
  $target->connection(@info);
  my %reg = %{ $class->_class_registrations };
  while (my ($comp, $comp_class) = each %reg) {
    my $target_class = "${target}::${comp}";
    {
      no strict 'refs';
      unshift(@{"${target_class}::ISA"}, $comp_class, $target);
    }
  }
}

1;
