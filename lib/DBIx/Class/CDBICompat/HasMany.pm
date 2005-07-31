package DBIx::Class::CDBICompat::HasMany;

use strict;
use warnings;

sub has_many {
  my ($class, $rel, $f_class, $f_key, $args) = @_;

  my $self_key;

  if (ref $f_class eq 'ARRAY') {
    ($f_class, $self_key) = @$f_class;
  }

  if (!$self_key || $self_key eq 'id') {
    my ($pri, $too_many) = keys %{ $class->_primaries };
    die "has_many only works with a single primary key; ${class} has more"
      if $too_many;
    $self_key = $pri;
  }
    
  eval "require $f_class";

  if (ref $f_key eq 'HASH') { $args = $f_key; undef $f_key; };

  #unless ($f_key) { Not selective enough. Removed pending fix.
  #  ($f_rel) = grep { $_->{class} && $_->{class} eq $class }
  #               $f_class->_relationships;
  #}

  unless ($f_key) {
    #warn join(', ', %{ $f_class->_columns });
    $class =~ /([^\:]+)$/;
    #warn $1;
    $f_key = lc $1 if $f_class->_columns->{lc $1};
  }

  die "Unable to resolve foreign key for has_many from ${class} to ${f_class}"
    unless $f_key;
  die "No such column ${f_key} on foreign class ${f_class}"
    unless $f_class->_columns->{$f_key};
  $class->add_relationship($rel, $f_class,
                            { "foreign.${f_key}" => "self.${self_key}" },
                            { _type => 'has_many', %{$args || {}} } );
  {
    no strict 'refs';
    *{"${class}::${rel}"} = sub { shift->search_related($rel, @_); };
    *{"${class}::add_to_${rel}"} = sub { shift->create_related($rel, @_); };
  }
  return 1;
}

sub delete {
  my ($self, @rest) = @_;
  return $self->NEXT::ACTUAL::delete(@rest) unless ref $self;
    # I'm just ignoring this for class deletes because hell, the db should
    # be handling this anyway. Assuming we have joins we probably actually
    # *could* do them, but I'd rather not.

  my $ret = $self->NEXT::ACTUAL::delete(@rest);

  my %rels = %{ $self->_relationships };
  my @hm = grep { $rels{$_}{attrs}{_type}
                   && $rels{$_}{attrs}{_type} eq 'has_many' } keys %rels;
  foreach my $has_many (@hm) {
    unless ($rels{$has_many}->{attrs}{no_cascade_delete}) {
      $_->delete for $self->search_related($has_many)
    }
  }
  return $ret;
}
1;
