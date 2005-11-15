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

=over 4

=item add_relationship

  __PACKAGE__->add_relationship('relname', 'Foreign::Class', $cond, $attrs);

The condition needs to be an SQL::Abstract-style representation of the
join between the tables - for example if you're creating a rel from Foo to Bar

  { 'foreign.foo_id' => 'self.id' }

will result in a JOIN clause like

  foo me JOIN bar bar ON bar.foo_id = me.id

=cut

sub add_relationship {
  my ($class, $rel, $f_class, $cond, $attrs) = @_;
  die "Can't create relationship without join condition" unless $cond;
  $attrs ||= {};
  eval "require $f_class;";
  my %rels = %{ $class->_relationships };
  $rels{$rel} = { class => $f_class,
                  cond  => $cond,
                  attrs => $attrs };
  $class->_relationships(\%rels);

  return unless eval { $f_class->can('columns'); }; # Foreign class not loaded
  eval { $class->_resolve_join($rel, 'me') };

  if ($@) { # If the resolve failed, back out and re-throw the error
    delete $rels{$rel}; # 
    $class->_relationships(\%rels);
    $class->throw("Error creating relationship $rel: $@");
  }
  1;
}

sub _resolve_join {
  my ($class, $join, $alias) = @_;
  if (ref $join eq 'ARRAY') {
    return map { $class->_resolve_join($_, $alias) } @$join;
  } elsif (ref $join eq 'HASH') {
    return map { $class->_resolve_join($_, $alias),
                 $class->_relationships->{$_}{class}->_resolve_join($join->{$_}, $_) }
           keys %$join;
  } elsif (ref $join) {
    $class->throw("No idea how to resolve join reftype ".ref $join);
  } else {
    my $rel_obj = $class->_relationships->{$join};
    $class->throw("No such relationship ${join}") unless $rel_obj;
    my $j_class = $rel_obj->{class};
    my %join = (_action => 'join',
         _aliases => { 'self' => $alias, 'foreign' => $join },
         _classes => { $alias => $class, $join => $j_class });
    my $j_cond = $j_class->resolve_condition($rel_obj->{cond}, \%join);
    return [ { $join => $j_class->_table_name,
               -join_type => $rel_obj->{attrs}{join_type} || '' }, $j_cond ];
  }
}

sub resolve_condition {
  my ($self, $cond, $attrs) = @_;
  if (ref $cond eq 'HASH') {
    my %ret;
    foreach my $key (keys %$cond) {
      my $val = $cond->{$key};
      if (ref $val) {
        $self->throw("Can't handle this yet :(");
      } else {
        $ret{$self->_cond_key($attrs => $key)}
          = $self->_cond_value($attrs => $key => $val);
      }
    }
    return \%ret;
  } else {
   $self->throw("Can't handle this yet :(");
  }
}

sub _cond_key {
  my ($self, $attrs, $key) = @_;
  my $action = $attrs->{_action} || '';
  if ($action eq 'convert') {
    unless ($key =~ s/^foreign\.//) {
      $self->throw("Unable to convert relationship to WHERE clause: invalid key ${key}");
    }
    return $key;
  } elsif ($action eq 'join') {
    return $key unless $key =~ /\./;
    my ($type, $field) = split(/\./, $key);
    if (my $alias = $attrs->{_aliases}{$type}) {
      my $class = $attrs->{_classes}{$alias};
      $self->throw("Unknown column $field on $class as $alias")
        unless $class->has_column($field);
      return join('.', $alias, $field);
    } else {
      $self->throw( "Unable to resolve type ${type}: only have aliases for ".
            join(', ', keys %{$attrs->{_aliases} || {}}) );
    }
  }
  return $self->next::method($attrs, $key);
}

sub _cond_value {
  my ($self, $attrs, $key, $value) = @_;
  my $action = $attrs->{_action} || '';
  if ($action eq 'convert') {
    unless ($value =~ s/^self\.//) {
      $self->throw( "Unable to convert relationship to WHERE clause: invalid value ${value}" );
    }
    unless ($self->has_column($value)) {
      $self->throw( "Unable to convert relationship to WHERE clause: no such accessor ${value}" );
    }
    return $self->get_column($value);
  } elsif ($action eq 'join') {
    return $key unless $key =~ /\./;
    my ($type, $field) = split(/\./, $value);
    if (my $alias = $attrs->{_aliases}{$type}) {
      my $class = $attrs->{_classes}{$alias};
      $self->throw("Unknown column $field on $class as $alias")
        unless $class->has_column($field);
      return join('.', $alias, $field);
    } else {
      $self->throw( "Unable to resolve type ${type}: only have aliases for ".
            join(', ', keys %{$attrs->{_aliases} || {}}) );
    }
  }
      
  return $self->next::method($attrs, $key, $value)
}

=item search_related

  My::Table->search_related('relname', $cond, $attrs);

=cut

sub search_related {
  my $self = shift;
  return $self->_query_related('search', @_);
}

=item count_related

  My::Table->count_related('relname', $cond, $attrs);

=cut

sub count_related {
  my $self = shift;
  return $self->_query_related('count', @_);
}

sub _query_related {
  my $self = shift;
  my $meth = shift;
  my $rel = shift;
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }
  my $rel_obj = $self->_relationships->{$rel};
  $self->throw( "No such relationship ${rel}" ) unless $rel_obj;
  $attrs = { %{$rel_obj->{attrs} || {}}, %{$attrs || {}} };

  $self->throw( "Invalid query: @_" ) if (@_ > 1 && (@_ % 2 == 1));
  my $query = ((@_ > 1) ? {@_} : shift);

  $attrs->{_action} = 'convert'; # shouldn't we resolve the cond to something
                                 # to merge into the AST really?
  my ($cond) = $self->resolve_condition($rel_obj->{cond}, $attrs);
  $query = ($query ? { '-and' => [ $cond, $query ] } : $cond);
  #use Data::Dumper; warn Dumper($query);
  #warn $rel_obj->{class}." $meth $cond ".join(', ', @{$attrs->{bind}||[]});
  delete $attrs->{_action};
  return $self->resolve_class($rel_obj->{class}
           )->$meth($query, $attrs);
}

=item create_related

  My::Table->create_related('relname', \%col_data);

=cut

sub create_related {
  my $class = shift;
  return $class->new_related(@_)->insert;
}

=item new_related

  My::Table->new_related('relname', \%col_data);

=cut

sub new_related {
  my ($self, $rel, $values, $attrs) = @_;
  $self->throw( "Can't call new_related as class method" ) 
    unless ref $self;
  $self->throw( "new_related needs a hash" ) 
    unless (ref $values eq 'HASH');
  my $rel_obj = $self->_relationships->{$rel};
  $self->throw( "No such relationship ${rel}" ) unless $rel_obj;
  $self->throw( "Can't abstract implicit create for ${rel}, condition not a hash" )
    unless ref $rel_obj->{cond} eq 'HASH';
  $attrs = { %{$rel_obj->{attrs}}, %{$attrs || {}}, _action => 'convert' };

  my %fields = %{$self->resolve_condition($rel_obj->{cond},$attrs)};
  $fields{$_} = $values->{$_} for keys %$values;

  return $self->resolve_class($rel_obj->{class})->new(\%fields);
}

=item find_related

  My::Table->find_related('relname', @pri_vals | \%pri_vals);

=cut

sub find_related {
  my $self = shift;
  my $rel = shift;
  my $rel_obj = $self->_relationships->{$rel};
  $self->throw( "No such relationship ${rel}" ) unless $rel_obj;
  my ($cond) = $self->resolve_condition($rel_obj->{cond}, { _action => 'convert' });
  $self->throw( "Invalid query: @_" ) if (@_ > 1 && (@_ % 2 == 1));
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }
  my $query = ((@_ > 1) ? {@_} : shift);
  $query = ($query ? { '-and' => [ $cond, $query ] } : $cond);
  return $self->resolve_class($rel_obj->{class})->find($query);
}

=item find_or_create_related

  My::Table->find_or_create_related('relname', \%col_data);

=cut

sub find_or_create_related {
  my $self = shift;
  return $self->find_related(@_) || $self->create_related(@_);
}

=item set_from_related

  My::Table->set_from_related('relname', $rel_obj);

=cut

sub set_from_related {
  my ($self, $rel, $f_obj) = @_;
  my $rel_obj = $self->_relationships->{$rel};
  $self->throw( "No such relationship ${rel}" ) unless $rel_obj;
  my $cond = $rel_obj->{cond};
  $self->throw( "set_from_related can only handle a hash condition; the "
    ."condition for $rel is of type ".(ref $cond ? ref $cond : 'plain scalar'))
      unless ref $cond eq 'HASH';
  my $f_class = $self->resolve_class($rel_obj->{class});
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

=item update_from_related

  My::Table->update_from_related('relname', $rel_obj);

=cut

sub update_from_related {
  my $self = shift;
  $self->set_from_related(@_);
  $self->update;
}

=item delete_related

  My::Table->delete_related('relname', $cond, $attrs);

=cut

sub delete_related {
  my $self = shift;
  return $self->search_related(@_)->delete;
}

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

