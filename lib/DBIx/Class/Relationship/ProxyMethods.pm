package # hide from PAUSE
    DBIx::Class::Relationship::ProxyMethods;

use strict;
use warnings;
use Sub::Name ();
use base qw/DBIx::Class/;

our %_pod_inherit_config =
  (
   class_map => { 'DBIx::Class::Relationship::ProxyMethods' => 'DBIx::Class::Relationship' }
  );

sub register_relationship {
  my ($class, $rel, $info) = @_;
  if (my $proxy_args = $info->{attrs}{proxy}) {
    $class->proxy_to_related($rel, $proxy_args);
  }
  $class->next::method($rel, $info);
}

sub proxy_to_related {
  my ($class, $rel, $proxy_args) = @_;
  my %proxy_map = $class->_build_proxy_map_from($proxy_args);
  no strict 'refs';
  no warnings 'redefine';
  foreach my $meth_name ( keys %proxy_map ) {
    my $proxy_to_col = $proxy_map{$meth_name};
    my $name = join '::', $class, $meth_name;
    *$name = Sub::Name::subname $name => sub {
      my $self = shift;
      my $relobj = $self->$rel;
      if (@_ && !defined $relobj) {
        $relobj = $self->create_related($rel, { $proxy_to_col => $_[0] });
        @_ = ();
      }
      return ($relobj ? $relobj->$proxy_to_col(@_) : undef);
   }
  }
}

sub _build_proxy_map_from {
  my ( $class, $proxy_arg ) = @_;
  my $ref = ref $proxy_arg;

  if ($ref eq 'HASH') {
    return %$proxy_arg;
  }
  elsif ($ref eq 'ARRAY') {
    return map {
      (ref $_ eq 'HASH')
        ? (%$_)
        : ($_ => $_)
    } @$proxy_arg;
  }
  elsif ($ref) {
    $class->throw_exception("Unable to process the 'proxy' argument $proxy_arg");
  }
  else {
    return ( $proxy_arg => $proxy_arg );
  }
}

1;
