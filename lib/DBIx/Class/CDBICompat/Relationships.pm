package # hide from PAUSE
    DBIx::Class::CDBICompat::Relationships;

use strict;
use warnings;

use base qw/Class::Data::Inheritable/;

use Clone;
use DBIx::Class::CDBICompat::Relationship;

__PACKAGE__->mk_classdata('__meta_info' => {});


=head1 NAME

DBIx::Class::CDBICompat::Relationships

=head1 DESCRIPTION

Emulate C<has_a>, C<has_many>, C<might_have> and C<meta_info>.

=cut

sub has_a {
  my ($self, $col, $f_class, %args) = @_;
  $self->throw_exception( "No such column ${col}" ) unless $self->has_column($col);
  $self->ensure_class_loaded($f_class);
  
  my $rel;

  if ($args{'inflate'} || $args{'deflate'}) { # Non-database has_a
    if (!ref $args{'inflate'}) {
      my $meth = $args{'inflate'};
      $args{'inflate'} = sub { $f_class->$meth(shift); };
    }
    if (!ref $args{'deflate'}) {
      my $meth = $args{'deflate'};
      $args{'deflate'} = sub { shift->$meth; };
    }
    $self->inflate_column($col, \%args);
    
    $rel = {
        class => $f_class
    };
  }
  else {
    $self->belongs_to($col, $f_class);
    $rel = $self->result_source_instance->relationship_info($col);
  }
  
  $self->_extend_meta(
    has_a => $col,
    $rel
  );
  
  return 1;
}


sub has_many {
  my ($class, $rel, $f_class, $f_key, $args) = @_;

  my @f_method;

  if (ref $f_class eq 'ARRAY') {
    ($f_class, @f_method) = @$f_class;
  }

  if (ref $f_key eq 'HASH' && !$args) { $args = $f_key; undef $f_key; };

  $args ||= {};
  if (delete $args->{no_cascade_delete}) {
    $args->{cascade_delete} = 0;
  }

  if( !$f_key and !@f_method ) {
      my $f_source = $f_class->result_source_instance;
      ($f_key) = grep { $f_source->relationship_info($_)->{class} eq $class }
                      $f_source->relationships;
  }

  $class->next::method($rel, $f_class, $f_key, $args);

  $class->_extend_meta(
    has_many => $rel,
    $class->result_source_instance->relationship_info($rel)
  );

  if (@f_method) {
    no strict 'refs';
    no warnings 'redefine';
    my $post_proc = sub { my $o = shift; $o = $o->$_ for @f_method; $o; };
    *{"${class}::${rel}"} =
      sub {
        my $rs = shift->search_related($rel => @_);
        $rs->{attrs}{record_filter} = $post_proc;
        return (wantarray ? $rs->all : $rs);
      };
    return 1;
  }

}


sub might_have {
  my ($class, $rel, $f_class, @columns) = @_;
  
  my $ret;
  if (ref $columns[0] || !defined $columns[0]) {
    $ret = $class->next::method($rel, $f_class, @columns);
  } else {
    $ret = $class->next::method($rel, $f_class, undef,
                                { proxy => \@columns });
  }
  
  $class->_extend_meta(
    might_have => $rel,
    $class->result_source_instance->relationship_info($rel)
  );
  
  return $ret;
}


sub _extend_meta {
    my ($class, $type, $rel, $val) = @_;
    my %hash = %{ Clone::clone($class->__meta_info || {}) };

    $val->{self_class} = $class;
    $val->{type}       = $type;
    $val->{accessor}   = $rel;

    $hash{$type}{$rel} = DBIx::Class::CDBICompat::Relationship->new($val);
    $class->__meta_info(\%hash);
}

sub meta_info {
    my ($class, $type, $rel) = @_;
    my $meta = $class->__meta_info;
    return $meta unless $type;

    my $type_meta = $meta->{$type};
    return $type_meta unless $rel;
    return $type_meta->{$rel};
}


sub search {
  my $self = shift;
  my $attrs = {};
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }
  my $where = (@_ ? ((@_ == 1) ? ((ref $_[0] eq "HASH") ? { %{+shift} } : shift)
                               : {@_})
                  : undef());
  if (ref $where eq 'HASH') {
    foreach my $key (keys %$where) { # has_a deflation hack
      $where->{$key} = ''.$where->{$key}
        if eval { $where->{$key}->isa('DBIx::Class') };
    }
  }
  $self->next::method($where, $attrs);
}

1;
