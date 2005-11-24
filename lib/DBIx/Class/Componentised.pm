package DBIx::Class::Componentised;

use Class::C3;

sub inject_base {
  my ($class, $target, @to_inject) = @_;
  {
    no strict 'refs';
    unshift(@{"${target}::ISA"}, grep { $target ne $_ } @to_inject);
  }
  my $table = { Class::C3::_dump_MRO_table };
  eval "package $target; import Class::C3;" unless exists $table->{$target};
  Class::C3::reinitialize() if defined $table->{$target};
}

sub load_components {
  my $class = shift;
  my @comp = map { "DBIx::Class::$_" } grep { $_ !~ /^#/ } @_;
  $class->_load_components(@comp);
}

sub load_own_components {
  my $class = shift;
  my @comp = map { "${class}::$_" } grep { $_ !~ /^#/ } @_;
  $class->_load_components(@comp);
}

sub _load_components {
  my ($class, @comp) = @_;
  foreach my $comp (@comp) {
    eval "use $comp";
    die $@ if $@;
  }
  $class->inject_base($class => @comp);
}

1;
