package DBIx::Class::Relationship::ManyToMany;

use strict;
use warnings;

sub many_to_many {
  my ($class, $meth, $rel, $f_rel, $rel_attrs) = @_;
  $rel_attrs ||= {};
  
  {
    no strict 'refs';
    no warnings 'redefine';
    *{"${class}::${meth}"} = sub {
      my ($self,$cond,$attrs) = @_;
      $self->search_related($rel)->search_related($f_rel, $cond, { %$rel_attrs, %{$attrs||{}} });
    };
  }
}

1;
