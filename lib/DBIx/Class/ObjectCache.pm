package DBIx::Class::ObjectCache;

use strict;
use warnings;

use base qw/Class::Data::Inheritable/;

__PACKAGE__->mk_classdata('cache');

=head1 NAME 

    DBIx::Class::ObjectCache - Cache rows by primary key (EXPERIMENTAL)

=head1 SYNOPSIS

    # in your class definition
    use Cache::FastMmmap;
    __PACKAGE__->cache(Cache::FastMmap->new);

=head1 DESCRIPTION

This class implements a simple object cache. It should be loaded before most (all?) other 
L<DBIx::Class> components. Note that, in its current state, this code is rather experimental. 
The only time the cache is made use of is on calls to $obj->find. This can still result in a 
significant savings, but more intelligent caching, e.g. of the resultset of a has_many call,
is currently not possible. It is not difficult, however, to implement additional caching
on top of this module. 

The cache is stored in a package variable called C<cache>. It can be set to any object that 
implements the required C<get>, C<set>, and C<remove> methods. 

=cut

sub insert {
  my $self = shift;
  $self->NEXT::ACTUAL::insert(@_);
  $self->_insert_into_cache if $self->cache;  
  return $self;
}

sub find {
  my ($self,@vals) = @_;
  return $self->NEXT::ACTUAL::find(@vals) unless $self->cache;
  
  # this is a terrible hack here. I know it can be improved.
  # but, it's a start anyway. probably find in PK.pm needs to
  # call a hook, or some such thing. -Dave/ningu
  my ($object,$key);
  my @pk = keys %{$self->_primaries};
  if (ref $vals[0] eq 'HASH') {
    my $cond = $vals[0]->{'-and'};
    $key = $self->_create_ID(%{$cond->[0]}) if ref $cond eq 'ARRAY';
  } elsif (@pk == @vals) {
    my %data;
    @data{@pk} = @vals;
    $key = $self->_create_ID(%data);
  } else {
    $key = $self->_create_ID(@vals);
  }
  if ($key and $object = $self->cache->get($key)) {
    #warn "retrieving cached item $key";
    return $object;
  }
  
  $object = $self->NEXT::ACTUAL::find(@vals);
  $object->_insert_into_cache if $object;
  return $object;
}

sub update {
  my $self = shift;
  my $new = $self->NEXT::ACTUAL::update(@_);
  $self->_insert_into_cache if $self->cache;
  return;
}

sub delete {
  my $self = shift;
  $self->cache->remove($self->ID) if $self->cache;
  return $self->NEXT::ACTUAL::delete(@_);
}

sub _row_to_object {
  my $self = shift;
  my $new = $self->NEXT::ACTUAL::_row_to_object(@_);
  $new->_insert_into_cache if $self->cache;
  return $new;
}

sub _insert_into_cache {
  my ($self) = @_;
  if (my $key = $self->ID) {
    my $object = bless { %$self }, ref $self;
    $self->cache->set($key,$object);
  }
}

1;

=head1 AUTHORS

David Kamholz <davekam@pobox.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
