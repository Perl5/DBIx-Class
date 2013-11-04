package # Hide from PAUSE
  DBIx::Class::SQLMaker::MySQL;

use Moo;
use namespace::clean;

extends 'DBIx::Class::SQLMaker';

has needs_inner_join => (is => 'rw', trigger => sub { shift->clear_renderer });

sub _build_converter_class {
  Module::Runtime::use_module('DBIx::Class::SQLMaker::Converter::MySQL');
}

sub _build_base_renderer_class {
  Module::Runtime::use_module('Data::Query::Renderer::SQL::MySQL');
}

around _renderer_args => sub {
  my ($orig, $self) = (shift, shift);
  +{ %{$self->$orig(@_)}, needs_inner_join => $self->needs_inner_join };
};

# Allow STRAIGHT_JOIN's
sub _generate_join_clause {
    my ($self, $join_type) = @_;

    if( $join_type && $join_type =~ /^STRAIGHT\z/i ) {
        return ' STRAIGHT_JOIN '
    }

    return $self->next::method($join_type);
}

# LOCK IN SHARE MODE
my $for_syntax = {
   update => 'FOR UPDATE',
   shared => 'LOCK IN SHARE MODE'
};

sub _lock_select {
   my ($self, $type) = @_;

   my $sql = $for_syntax->{$type}
    || $self->throw_exception("Unknown SELECT .. FOR type '$type' requested");

   return " $sql";
}

1;
