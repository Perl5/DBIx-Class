package DBIx::Class::Relationship::Base;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->mk_classdata('_relationships', { } );

=head1 NAME 

DBIx::Class::Relationship::Base - Inter-table relationships

=head1 SYNOPSIS

=head1 DESCRIPTION

This class handles relationships between the tables in your database
model. It allows your to set up relationships, and to perform joins
on searches.

=head1 METHODS

=head2 add_relationship

  __PACKAGE__->add_relationship('relname', 'Foreign::Class', $cond, $attrs);

The condition needs to be an SQL::Abstract-style representation of the
join between the tables. For example, if you're creating a rel from Foo to Bar,

  { 'foreign.foo_id' => 'self.id' }

will result in the JOIN clause

  foo me JOIN bar bar ON bar.foo_id = me.id

You can specify as many foreign => self mappings as necessary.

Valid attributes are as follows:

=over 4

=item join_type

Explicitly specifies the type of join to use in the relationship. Any SQL
join type is valid, e.g. C<LEFT> or C<RIGHT>. It will be placed in the SQL
command immediately before C<JOIN>.

=item proxy

An arrayref containing a list of accessors in the foreign class to proxy in
the main class. If, for example, you do the following:
  
  __PACKAGE__->might_have(bar => 'Bar', undef, { proxy => qw[/ margle /] });
  
Then, assuming Bar has an accessor named margle, you can do:

  my $obj = Foo->find(1);
  $obj->margle(10); # set margle; Bar object is created if it doesn't exist
  
=item accessor

Specifies the type of accessor that should be created for the relationship.
Valid values are C<single> (for when there is only a single related object),
C<multi> (when there can be many), and C<filter> (for when there is a single
related object, but you also want the relationship accessor to double as
a column accessor). For C<multi> accessors, an add_to_* method is also
created, which calls C<create_related> for the relationship.

=back

=head2 register_relationship($relname, $rel_info)

Registers a relationship on the class

=cut

sub register_relationship { }

=head2 search_related

  My::Table->search_related('relname', $cond, $attrs);

=cut

sub search_related {
  my $self = shift;
  die "Can't call *_related as class methods" unless ref $self;
  my $rel = shift;
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }
  my $rel_obj = $self->relationship_info($rel);
  $self->throw( "No such relationship ${rel}" ) unless $rel_obj;
  $attrs = { %{$rel_obj->{attrs} || {}}, %{$attrs || {}} };

  $self->throw( "Invalid query: @_" ) if (@_ > 1 && (@_ % 2 == 1));
  my $query = ((@_ > 1) ? {@_} : shift);

  my ($cond) = $self->result_source->resolve_condition($rel_obj->{cond}, $rel, $self);
  $query = ($query ? { '-and' => [ $cond, $query ] } : $cond);
  #use Data::Dumper; warn Dumper($cond);
  #warn $rel_obj->{class}." $meth $cond ".join(', ', @{$attrs->{bind}||[]});
  return $self->result_source->related_source($rel
           )->resultset->search($query, $attrs);
}

=head2 count_related

  $obj->count_related('relname', $cond, $attrs);

=cut

sub count_related {
  my $self = shift;
  return $self->search_related(@_)->count;
}

=head2 create_related

  My::Table->create_related('relname', \%col_data);

=cut

sub create_related {
  my $self = shift;
  my $rel = shift;
  return $self->search_related($rel)->create(@_);
}

=head2 new_related

  My::Table->new_related('relname', \%col_data);

=cut

sub new_related {
  my ($self, $rel, $values, $attrs) = @_;
  return $self->search_related($rel)->new($values, $attrs);
}

=head2 find_related

  My::Table->find_related('relname', @pri_vals | \%pri_vals);

=cut

sub find_related {
  my $self = shift;
  my $rel = shift;
  return $self->search_related($rel)->find(@_);
}

=head2 find_or_create_related

  My::Table->find_or_create_related('relname', \%col_data);

=cut

sub find_or_create_related {
  my $self = shift;
  return $self->find_related(@_) || $self->create_related(@_);
}

=head2 set_from_related

  My::Table->set_from_related('relname', $rel_obj);

=cut

sub set_from_related {
  my ($self, $rel, $f_obj) = @_;
  my $rel_obj = $self->relationship_info($rel);
  $self->throw( "No such relationship ${rel}" ) unless $rel_obj;
  my $cond = $rel_obj->{cond};
  $self->throw( "set_from_related can only handle a hash condition; the "
    ."condition for $rel is of type ".(ref $cond ? ref $cond : 'plain scalar'))
      unless ref $cond eq 'HASH';
  my $f_class = $self->result_source->schema->class($rel_obj->{class});
  $self->throw( "Object $f_obj isn't a ".$f_class )
    unless $f_obj->isa($f_class);
  foreach my $key (keys %$cond) {
    next if ref $cond->{$key}; # Skip literals and complex conditions
    $self->throw("set_from_related can't handle $key as key")
      unless $key =~ m/^foreign\.([^\.]+)$/;
    my $val = $f_obj->get_column($1);
    $self->throw("set_from_related can't handle ".$cond->{$key}." as value")
      unless $cond->{$key} =~ m/^self\.([^\.]+)$/;
    $self->set_column($1 => $val);
  }
  return 1;
}

=head2 update_from_related

  My::Table->update_from_related('relname', $rel_obj);

=cut

sub update_from_related {
  my $self = shift;
  $self->set_from_related(@_);
  $self->update;
}

=head2 delete_related

  My::Table->delete_related('relname', $cond, $attrs);

=cut

sub delete_related {
  my $self = shift;
  return $self->search_related(@_)->delete;
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

