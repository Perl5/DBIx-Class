package DBIx::Class::CDBICompat::HasA;

use strict;
use warnings;

sub has_a {
  my ($self, $col, $f_class) = @_;
  die "No such column ${col}" unless $self->_columns->{$col};
  eval "require $f_class";
  my ($pri, $too_many) = keys %{ $f_class->_primaries };
  die "has_a only works with a single primary key; ${f_class} has more"
    if $too_many;
  $self->add_relationship($col, $f_class,
                            { "foreign.${pri}" => "self.${col}" },
                            { _type => 'has_a' } );
  $self->delete_accessor($col);
  $self->mk_group_accessors('has_a' => $col);
  return 1;
}

sub get_has_a {
  my ($self, $rel) = @_;
  #warn $rel;
  #warn join(', ', %{$self->{_column_data}});
  return $self->{_relationship_data}{$rel}
    if $self->{_relationship_data}{$rel};
  return undef unless $self->get_column($rel);
  #my ($pri) = (keys %{$self->_relationships->{$rel}{class}->_primaries})[0];
  return $self->{_relationship_data}{$rel} =
           ($self->search_related($rel, {}, {}))[0]
           || do { 
                my $f_class = $self->_relationships->{$rel}{class};
                my ($pri) = keys %{$f_class->_primaries};
                $f_class->new({ $pri => $self->get_column($rel) }); };
}

sub set_has_a {
  my ($self, $rel, @rest) = @_;
  my $ret = $self->store_has_a($rel, @rest);
  $self->{_dirty_columns}{$rel} = 1;
  return $ret;
}

sub store_has_a {
  my ($self, $rel, $obj) = @_;
  return $self->set_column($rel, $obj) unless ref $obj;
  my $rel_obj = $self->_relationships->{$rel};
  die "Can't set $rel: object $obj is not of class ".$rel_obj->{class}
     unless $obj->isa($rel_obj->{class});
  $self->{_relationship_data}{$rel} = $obj;
  $self->set_column($rel, ($obj->_ident_values)[0]);
  return $obj;
}

sub new {
  my ($class, $attrs, @rest) = @_;
  my %hasa;
  foreach my $key (keys %$attrs) {
    my $rt = $class->_relationships->{$key}{attrs}{_type};
    next unless $rt && $rt eq 'has_a' && ref $attrs->{$key};
    $hasa{$key} = delete $attrs->{$key};
  }
  my $new = $class->NEXT::ACTUAL::new($attrs, @rest);
  foreach my $key (keys %hasa) {
    $new->store_has_a($key, $hasa{$key});
  }
  return $new;
}

sub _cond_value {
  my ($self, $attrs, $key, $value) = @_;
  if ( my $rel_obj = $self->_relationships->{$key} ) {
    my $rel_type = $rel_obj->{attrs}{_type} || '';
    if ($rel_type eq 'has_a' && ref $value) {
      die "Object $value is not of class ".$rel_obj->{class}
         unless $value->isa($rel_obj->{class});
      $value = ($value->_ident_values)[0];
      #warn $value;
    }
  }
  return $self->NEXT::ACTUAL::_cond_value($attrs, $key, $value);
}

1;
