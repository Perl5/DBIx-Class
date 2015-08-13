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

      # this little horror is there replicating a deprecation from
      # within search_rs() itself
      shift->search_related_rs($rel)
            ->search_related_rs(
              $f_rel,
              undef,
              ( @_ > 1 and ref $_[-1] eq 'HASH' )
                ? { %$rel_attrs, %{ pop @_ } }
                : $rel_attrs
            )->search_rs(@_)
      ;

    };


    my $meth_name = join '::', $class, $meth;
    *$meth_name = subname $meth_name, sub {

      DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_WANTARRAY and my $sog = fail_on_internal_wantarray;

      my $rs = shift->$rs_meth( @_ );

      wantarray ? $rs->all : $rs;

    };


    my $add_meth_name = join '::', $class, $add_meth;
    *$add_meth_name = subname $add_meth_name, sub {

      ( @_ >= 2 and @_ <= 3 ) or $_[0]->throw_exception(
        "'$add_meth' expects an object or hashref to link to, and an optional hashref of link data"
      );

      $_[0]->throw_exception(
        "The optional link data supplied to '$add_meth' is not a hashref (it was previously ignored)"
      ) if $_[2] and ref $_[2] ne 'HASH';

      my( $self, $far_obj ) = @_;

      my $guard;

      # the API needs is always expected to return the far object, possibly
      # creating it in the process
      if( not defined blessed $far_obj ) {

        $guard = $self->result_source->schema->storage->txn_scope_guard;

        # reify the hash into an actual object
        $far_obj = $self->result_source
                         ->related_source( $rel )
                          ->related_source( $f_rel )
                           ->resultset
                            ->search_rs( undef, $rel_attrs )
                             ->find_or_create( $far_obj );
      }

      my $link = $self->new_related(
        $rel,
        $_[2] || {},
      );

      $link->set_from_related( $f_rel, $far_obj );

      $link->insert();

      $guard->commit if $guard;

      $far_obj;
    };


    my $set_meth_name = join '::', $class, $set_meth;
    *$set_meth_name = subname $set_meth_name, sub {

      my $self = shift;

      my $set_to = ( ref $_[0] eq 'ARRAY' )
        ? ( shift @_ )
        : do {
          carp_unique(
            "Calling '$set_meth' with a list of items to link to is deprecated, use an arrayref instead"
          );

          # gobble up everything from @_ into a new arrayref
          [ splice @_ ]
        }
      ;

      # make sure folks are not invoking a bizarre mix of deprecated and curent syntax
      $self->throw_exception(
        "'$set_meth' expects an arrayref of objects or hashrefs to link to, and an optional hashref of link data"
      ) if (
        @_ > 1
          or
        ( @_ and ref $_[0] ne 'HASH' )
      );

      my $guard;

      # there will only be a single delete() op, unless we have what to set to
      $guard = $self->result_source->schema->storage->txn_scope_guard
        if @$set_to;

      # if there is a where clause in the attributes, ensure we only delete
      # rows that are within the where restriction
      $self->search_related(
        $rel,
        ( $rel_attrs->{where}
          ? ( $rel_attrs->{where}, { join => $f_rel } )
          : ()
        )
      )->delete;

      # add in the set rel objects
      $self->$add_meth(
        $_,
        @_, # at this point @_ is either empty or contains a lone link-data hash
      ) for @$set_to;

      $guard->commit if $guard;
    };


    my $remove_meth_name = join '::', $class, $remove_meth;
    *$remove_meth_name = subname $remove_meth_name, sub {

      $_[0]->throw_exception("'$remove_meth' expects an object")
        unless defined blessed $_[1];

      $_[0]->search_related_rs( $rel )
            ->search_rs( $_[1]->ident_condition( $f_rel ), { join => $f_rel } )
             ->delete;
    };

  }
}

1;
