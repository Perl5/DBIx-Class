package # hide from PAUSE
    DBIx::Class::Relationship::ManyToMany;

use strict;
use warnings;

sub many_to_many {
  my ($class, $meth, $rel, $f_rel, $rel_attrs) = @_;
  {
    no strict 'refs';
    no warnings 'redefine';

    *{"${class}::${meth}"} = sub {
      my $self = shift;
      my $attrs = @_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {};
      $self->search_related($rel)->search_related(
        $f_rel, @_ > 0 ? @_ : undef, { %{$rel_attrs||{}}, %$attrs }
      );
    };

    *{"${class}::add_to_${meth}"} = sub {
      my( $self, $obj ) = @_;
      my $vals = @_ > 2 && ref $_[$#_] eq 'HASH' ? pop(@_) : {};
      return $self->search_related($rel)->create({
        map { $_=>$self->get_column($_) } $self->primary_columns(),
        map { $_=>$obj->get_column($_) } $obj->primary_columns(),
        %$vals,
      });
    };

    *{"${class}::remove_from_${meth}"} = sub {
      my( $self, $obj ) = @_;
      return $self->search_related(
        $rel,
        {
            map { $_=>$self->get_column($_) } $self->primary_columns(),
            map { $_=>$obj->get_column($_) } $obj->primary_columns(),
        },
      )->delete();
    };

  }
}

1;
