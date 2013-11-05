package # hide from PAUSE
    DBIx::Class::Relationship::Accessor;

use strict;
use warnings;
use Sub::Name;
use DBIx::Class::Carp;
use DBIx::Class::_Util 'fail_on_internal_wantarray';
use namespace::clean;

our %_pod_inherit_config =
  (
   class_map => { 'DBIx::Class::Relationship::Accessor' => 'DBIx::Class::Relationship' }
  );

sub register_relationship {
  my ($class, $rel, $info) = @_;
  if (my $acc_type = $info->{attrs}{accessor}) {
    $class->add_relationship_accessor($rel => $acc_type);
  }
  $class->next::method($rel => $info);
}

sub add_relationship_accessor {
  my ($class, $rel, $acc_type) = @_;
  my %meth;
  if ($acc_type eq 'single') {
    my $rel_info = $class->relationship_info($rel);
    $meth{$rel} = sub {
      my $self = shift;
      if (@_) {
        $self->set_from_related($rel, @_);
        return $self->{_relationship_data}{$rel} = $_[0];
      } elsif (exists $self->{_relationship_data}{$rel}) {
        return $self->{_relationship_data}{$rel};
      } else {
        my $cond = $self->result_source->_resolve_condition(
          $rel_info->{cond}, $rel, $self, $rel
        );
        if ($rel_info->{attrs}->{undef_on_null_fk}){
          return undef unless ref($cond) eq 'HASH';
          return undef if grep { not defined $_ } values %$cond;
        }
        my $val = $self->find_related($rel, {}, {});
        return $val unless $val;  # $val instead of undef so that null-objects can go through

        return $self->{_relationship_data}{$rel} = $val;
      }
    };
  } elsif ($acc_type eq 'filter') {
    $class->throw_exception("No such column '$rel' to filter")
       unless $class->has_column($rel);
    my $f_class = $class->relationship_info($rel)->{class};
    $class->inflate_column($rel,
      { inflate => sub {
          my ($val, $self) = @_;
          return $self->find_or_new_related($rel, {}, {});
        },
        deflate => sub {
          my ($val, $self) = @_;
          $self->throw_exception("'$val' isn't a $f_class") unless $val->isa($f_class);

          # MASSIVE FIXME - this code assumes we pointed at the PK, but the belongs_to
          # helper does not check any of this
          # fixup the code a bit to make things saner, but ideally 'filter' needs to
          # be deprecated ASAP and removed shortly after
          # Not doing so before 0.08250 however, too many things in motion already
          my ($pk_col, @rest) = $val->result_source->_pri_cols_or_die;
          $self->throw_exception(
            "Relationship '$rel' of type 'filter' can not work with a multicolumn primary key on source '$f_class'"
          ) if @rest;

          my $pk_val = $val->get_column($pk_col);
          carp_unique (
            "Unable to deflate 'filter'-type relationship '$rel' (related object "
          . "primary key not retrieved), assuming undef instead"
          ) if ( ! defined $pk_val and $val->in_storage );

          return $pk_val;
        }
      }
    );
  } elsif ($acc_type eq 'multi') {
    $meth{$rel} = sub {
      DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_WANTARRAY and wantarray and my $sog = fail_on_internal_wantarray($_[0]);
      shift->search_related($rel, @_)
    };
    $meth{"${rel}_rs"} = sub { shift->search_related_rs($rel, @_) };
    $meth{"add_to_${rel}"} = sub { shift->create_related($rel, @_); };
  } else {
    $class->throw_exception("No such relationship accessor type '$acc_type'");
  }
  {
    no strict 'refs';
    no warnings 'redefine';
    foreach my $meth (keys %meth) {
      my $name = join '::', $class, $meth;
      *$name = subname($name, $meth{$meth});
    }
  }
}

1;
