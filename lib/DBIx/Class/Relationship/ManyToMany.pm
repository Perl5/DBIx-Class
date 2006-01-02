package DBIx::Class::Relationship::ManyToMany;

use strict;
use warnings;

sub many_to_many {
  my ($class, $meth, $rel_class, $f_class) = @_;
  
  eval "require $f_class";
  
  {
    no strict 'refs';
    no warnings 'redefine';
    *{"${class}::${meth}"} =
      sub { shift->search_related($rel_class)->search_related($f_class, @_); };
  }
}

1;
