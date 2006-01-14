package DBIx::Class::ResultSource;

use strict;
use warnings;

use DBIx::Class::ResultSet;

use Carp qw/croak/;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' =>
  qw/_ordered_columns _columns _primaries name resultset_class result_class schema from _relationships/);

=head1 NAME 

DBIx::Class::ResultSource - Result source object

=head1 SYNOPSIS

=head1 DESCRIPTION

A ResultSource is a component of a schema from which results can be directly
retrieved, most usually a table (see L<DBIx::Class::ResultSource::Table>)

=head1 METHODS

=cut

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;
  my $new = bless({ %{$attrs || {}} }, $class);
  $new->{resultset_class} ||= 'DBIx::Class::ResultSet';
  $new->{_ordered_columns} ||= [];
  $new->{_columns} ||= {};
  $new->{_relationships} ||= {};
  $new->{name} ||= "!!NAME NOT SET!!";
  return $new;
}

sub add_columns {
  my ($self, @cols) = @_;
  $self->_ordered_columns( \@cols )
    if !$self->_ordered_columns;
  push @{ $self->_ordered_columns }, @cols;
  while (my $col = shift @cols) {

    my $column_info = ref $cols[0] ? shift : {};
      # If next entry is { ... } use that for the column info, if not
      # use an empty hashref

    $self->_columns->{$col} = $column_info;
  }
}

*add_column = \&add_columns;

=head2 add_columns

  $table->add_columns(qw/col1 col2 col3/);

  $table->add_columns('col1' => \%col1_info, 'col2' => \%col2_info, ...);

Adds columns to the result source. If supplied key => hashref pairs uses
the hashref as the column_info for that column.

=head2 add_column

  $table->add_column('col' => \%info?);

Convenience alias to add_columns

=cut

sub resultset {
  my $self = shift;
  return $self->resultset_class->new($self);
}

=head2 has_column

  if ($obj->has_column($col)) { ... }                                           
                                                                                
Returns 1 if the source has a column of this name, 0 otherwise.
                                                                                
=cut                                                                            

sub has_column {
  my ($self, $column) = @_;
  return exists $self->_columns->{$column};
}

=head2 column_info 

  my $info = $obj->column_info($col);                                           

Returns the column metadata hashref for a column.
                                                                                
=cut                                                                            

sub column_info {
  my ($self, $column) = @_;
  croak "No such column $column" unless exists $self->_columns->{$column};
  return $self->_columns->{$column};
}

=head2 columns

  my @column_names = $obj->columns;                                             
                                                                                
=cut                                                                            

sub columns {
  croak "columns() is a read-only accessor, did you mean add_columns()?" if (@_ > 1);
  return keys %{shift->_columns};
}

=head2 ordered_columns

  my @column_names = $obj->ordered_columns;

Like columns(), but returns column names using the order in which they were
originally supplied to add_columns().

=cut

sub ordered_columns {
  return @{shift->{_ordered_columns}||[]};
}

=head2 set_primary_key(@cols)                                                   
                                                                                
Defines one or more columns as primary key for this source. Should be
called after C<add_columns>.
                                                                                
=cut                                                                            

sub set_primary_key {
  my ($self, @cols) = @_;
  # check if primary key columns are valid columns
  for (@cols) {
    $self->throw("No such column $_ on table ".$self->name)
      unless $self->has_column($_);
  }
  $self->_primaries(\@cols);
}

=head2 primary_columns                                                          
                                                                                
Read-only accessor which returns the list of primary keys.
                                                                                
=cut                                                                            

sub primary_columns {
  return @{shift->_primaries||[]};
}

=head2 from

Returns an expression of the source to be supplied to storage to specify
retrieval from this source; in the case of a database the required FROM clause
contents.

=cut

=head2 storage

Returns the storage handle for the current schema

=cut

sub storage { shift->schema->storage; }

=head2 add_relationship

  $source->add_relationship('relname', 'related_source', $cond, $attrs);

The relation name can be arbitrary, but must be unique for each relationship
attached to this result source. 'related_source' should be the name with
which the related result source was registered with the current schema
(for simple schemas this is usally either Some::Namespace::Foo or just Foo)

The condition needs to be an SQL::Abstract-style representation of the join
between the tables. For example, if you're creating a rel from Foo to Bar,

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

=cut

sub add_relationship {
  my ($self, $rel, $f_source_name, $cond, $attrs) = @_;
  die "Can't create relationship without join condition" unless $cond;
  $attrs ||= {};

  my %rels = %{ $self->_relationships };
  $rels{$rel} = { class => $f_source_name,
                  source => $f_source_name,
                  cond  => $cond,
                  attrs => $attrs };
  $self->_relationships(\%rels);

  return 1;

  # XXX disabled. doesn't work properly currently. skip in tests.

  my $f_source = $self->schema->source($f_source_name);
  unless ($f_source) {
    eval "require $f_source_name;";
    if ($@) {
      die $@ unless $@ =~ /Can't locate/;
    }
    $f_source = $f_source_name->result_source;
    #my $s_class = ref($self->schema);
    #$f_source_name =~ m/^${s_class}::(.*)$/;
    #$self->schema->register_class(($1 || $f_source_name), $f_source_name);
    #$f_source = $self->schema->source($f_source_name);
  }
  return unless $f_source; # Can't test rel without f_source

  eval { $self->resolve_join($rel, 'me') };

  if ($@) { # If the resolve failed, back out and re-throw the error
    delete $rels{$rel}; # 
    $self->_relationships(\%rels);
    die "Error creating relationship $rel: $@";
  }
  1;
}

=head2 relationships()

Returns all valid relationship names for this source

=cut

sub relationships {
  return keys %{shift->_relationships};
}

=head2 relationship_info($relname)

Returns the relationship information for the specified relationship name

=cut

sub relationship_info {
  my ($self, $rel) = @_;
  return $self->_relationships->{$rel};
} 

=head2 has_relationship($rel)

Returns 1 if the source has a relationship of this name, 0 otherwise.
                                                                                
=cut                                                                            

sub has_relationship {
  my ($self, $rel) = @_;
  return exists $self->_relationships->{$rel};
}

=head2 resolve_join($relation)

Returns the join structure required for the related result source

=cut

sub resolve_join {
  my ($self, $join, $alias) = @_;
  if (ref $join eq 'ARRAY') {
    return map { $self->resolve_join($_, $alias) } @$join;
  } elsif (ref $join eq 'HASH') {
    return map { $self->resolve_join($_, $alias),
                 $self->related_source($_)->resolve_join($join->{$_}, $_) }
           keys %$join;
  } elsif (ref $join) {
    die("No idea how to resolve join reftype ".ref $join);
  } else {
    my $rel_info = $self->relationship_info($join);
    die("No such relationship ${join}") unless $rel_info;
    my $type = $rel_info->{attrs}{join_type} || '';
    return [ { $join => $self->related_source($join)->from,
               -join_type => $type },
             $self->resolve_condition($rel_info->{cond}, $join, $alias) ];
  }
}

=head2 resolve_condition($cond, $rel, $alias|$object)

Resolves the passed condition to a concrete query fragment. If given an alias,
returns a join condition; if given an object, inverts that object to produce
a related conditional from that object.

=cut

sub resolve_condition {
  my ($self, $cond, $rel, $for) = @_;
  #warn %$cond;
  if (ref $cond eq 'HASH') {
    my %ret;
    while (my ($k, $v) = each %{$cond}) {
      # XXX should probably check these are valid columns
      $k =~ s/^foreign\.// || die "Invalid rel cond key ${k}";
      $v =~ s/^self\.// || die "Invalid rel cond val ${v}";
      if (ref $for) { # Object
        #warn "$self $k $for $v";
        $ret{$k} = $for->get_column($v);
        #warn %ret;
      } else {
        $ret{"${rel}.${k}"} = "${for}.${v}";
      }
    }
    return \%ret;
  } else {
   die("Can't handle this yet :(");
  }
}


=head2 related_source($relname)

Returns the result source for the given relationship

=cut

sub related_source {
  my ($self, $rel) = @_;
  return $self->schema->source($self->relationship_info($rel)->{source});
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

