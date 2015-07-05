package # hide from PAUSE
    DBIx::Class::Relationship::ManyToMany;

use strict;
use warnings;

use DBIx::Class::Carp;
use Sub::Name 'subname';
use Scalar::Util 'blessed';
use DBIx::Class::_Util 'fail_on_internal_wantarray';
use namespace::clean;

our %_pod_inherit_config =
  (
   class_map => { 'DBIx::Class::Relationship::ManyToMany' => 'DBIx::Class::Relationship' }
  );

sub many_to_many {
  my ($class, $meth, $rel, $f_rel, $rel_attrs) = @_;

  $class->throw_exception(
    "missing relation in many-to-many"
  ) unless $rel;

  $class->throw_exception(
    "missing foreign relation in many-to-many"
  ) unless $f_rel;

  {
    no strict 'refs';
    no warnings 'redefine';

    my $add_meth = "add_to_${meth}";
    my $remove_meth = "remove_from_${meth}";
    my $set_meth = "set_${meth}";
    my $rs_meth = "${meth}_rs";

    for ($add_meth, $remove_meth, $set_meth, $rs_meth) {
      if ( $class->can ($_) ) {
        carp (<<"EOW") unless $ENV{DBIC_OVERWRITE_HELPER_METHODS_OK};

***************************************************************************
The many-to-many relationship '$meth' is trying to create a utility method
called $_.
This will completely overwrite one such already existing method on class
$class.

You almost certainly want to rename your method or the many-to-many
relationship, as the functionality of the original method will not be
accessible anymore.

To disable this warning set to a true value the environment variable
DBIC_OVERWRITE_HELPER_METHODS_OK

***************************************************************************
EOW
      }
    }

    $rel_attrs->{alias} ||= $f_rel;

    my $rs_meth_name = join '::', $class, $rs_meth;
    *$rs_meth_name = subname $rs_meth_name, sub {
      my $self = shift;
      my $attrs = @_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {};
      my $rs = $self->search_related($rel)->search_related(
        $f_rel, @_ > 0 ? @_ : undef, { %{$rel_attrs||{}}, %$attrs }
      );
      return $rs;
    };

    my $meth_name = join '::', $class, $meth;
    *$meth_name = subname $meth_name, sub {
      DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_WANTARRAY and my $sog = fail_on_internal_wantarray;
      my $self = shift;
      my $rs = $self->$rs_meth( @_ );
      return (wantarray ? $rs->all : $rs);
    };

    my $add_meth_name = join '::', $class, $add_meth;
    *$add_meth_name = subname $add_meth_name, sub {
      my $self = shift;
      @_ or $self->throw_exception(
        "${add_meth} needs an object or hashref"
      );

      my $link = $self->new_related( $rel,
        ( @_ > 1 && ref $_[-1] eq 'HASH' )
          ? pop
          : {}
      );

      my $far_obj = defined blessed $_[0]
        ? $_[0]
        : $self->result_source
                ->related_source( $rel )
                 ->related_source( $f_rel )
                  ->resultset->search_rs( {}, $rel_attrs||{} )
                   ->find_or_create( ref $_[0] eq 'HASH' ? $_[0] : {@_} )
      ;

      $link->set_from_related($f_rel, $far_obj);

      $link->insert();

      return $far_obj;
    };

    my $set_meth_name = join '::', $class, $set_meth;
    *$set_meth_name = subname $set_meth_name, sub {
      my $self = shift;
      @_ > 0 or $self->throw_exception(
        "{$set_meth} needs a list of objects or hashrefs"
      );

      my $guard = $self->result_source->schema->storage->txn_scope_guard;

      # if there is a where clause in the attributes, ensure we only delete
      # rows that are within the where restriction

      if ($rel_attrs && $rel_attrs->{where}) {
        $self->search_related( $rel, $rel_attrs->{where},{join => $f_rel})->delete;
      } else {
        $self->search_related( $rel, {} )->delete;
      }
      # add in the set rel objects
      $self->$add_meth($_, ref($_[1]) ? $_[1] : {})
        for ( ref($_[0]) eq 'ARRAY' ? @{ $_[0] } : @_ );

      $guard->commit;
    };

    my $remove_meth_name = join '::', $class, $remove_meth;
    *$remove_meth_name = subname $remove_meth_name, sub {
      my ($self, $obj) = @_;

      $self->throw_exception("${remove_meth} needs an object")
        unless blessed ($obj);

      $self->search_related_rs($rel)->search_rs(
        $obj->ident_condition( $f_rel ),
        { join => $f_rel },
      )->delete;
    };
  }
}

1;
