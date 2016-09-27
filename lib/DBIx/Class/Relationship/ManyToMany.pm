package # hide from PAUSE
    DBIx::Class::Relationship::ManyToMany;

use strict;
use warnings;

use DBIx::Class::Carp;
use DBIx::Class::_Util qw( quote_sub perlstring );

# FIXME - this should go away
# instead Carp::Skip should export usable keywords or something like that
my $unique_carper;
BEGIN { $unique_carper = \&carp_unique }

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

    my @main_meth_qsub_args = (
      {},
      { attributes => [
        'DBIC_method_is_indirect_sugar',
        ( keys( %{$rel_attrs||{}} )
          ? 'DBIC_method_is_m2m_sugar_with_attrs'
          : 'DBIC_method_is_m2m_sugar'
        ),
      ] },
    );


    quote_sub "${class}::${meth}", sprintf( <<'EOC', $rs_meth ), @main_meth_qsub_args;

      DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and DBIx::Class::_Util::fail_on_internal_call;
      DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_WANTARRAY and my $sog = DBIx::Class::_Util::fail_on_internal_wantarray;

      my $rs = shift->%s( @_ );

      wantarray ? $rs->all : $rs;
EOC


    my @extra_meth_qsub_args = (
      {
        '$rel_attrs' => \{ alias => $f_rel, %{ $rel_attrs||{} } },
        '$carp_unique' => \$unique_carper,
      },
      { attributes => [
        'DBIC_method_is_indirect_sugar',
        ( keys( %{$rel_attrs||{}} )
          ? 'DBIC_method_is_m2m_extra_sugar_with_attrs'
          : 'DBIC_method_is_m2m_extra_sugar'
        ),
      ] },
    );


    quote_sub "${class}::${rs_meth}", sprintf( <<'EOC', map { perlstring $_ } ( "${class}::${meth}", $rel, $f_rel ) ), @extra_meth_qsub_args;

      DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS
        and
      # allow nested calls from our ->many_to_many, see comment below
      ( (CORE::caller(1))[3] ne %s )
        and
      DBIx::Class::_Util::fail_on_internal_call;

      # this little horror is there replicating a deprecation from
      # within search_rs() itself
      shift->related_resultset( %s )
            ->related_resultset( %s )
             ->search_rs (
               undef,
               ( @_ > 1 and ref $_[-1] eq 'HASH' )
                 ? { %%$rel_attrs, %%{ pop @_ } }
                 : $rel_attrs
             )->search_rs(@_)
      ;
EOC

    # the above is the only indirect method, the 3 below have too much logic
    shift @{$extra_meth_qsub_args[1]{attributes}};


    quote_sub "${class}::${add_meth}", sprintf( <<'EOC', $add_meth, $rel, $f_rel ), @extra_meth_qsub_args;

      ( @_ >= 2 and @_ <= 3 ) or $_[0]->throw_exception(
        "'%1$s' expects an object or hashref to link to, and an optional hashref of link data"
      );

      $_[0]->throw_exception(
        "The optional link data supplied to '%1$s' is not a hashref (it was previously ignored)"
      ) if $_[2] and ref $_[2] ne 'HASH';

      my( $self, $far_obj ) = @_;

      my $guard;

      # the API is always expected to return the far object, possibly
      # creating it in the process
      if( not defined Scalar::Util::blessed( $far_obj ) ) {

        $guard = $self->result_source->schema->storage->txn_scope_guard;

        # reify the hash into an actual object
        $far_obj = $self->result_source
                         ->related_source( q{%2$s} )
                          ->related_source( q{%3$s} )
                           ->resultset
                            ->search_rs( undef, $rel_attrs )
                             ->find_or_create( $far_obj );
      }

      my $link = $self->new_related(
        q{%2$s},
        $_[2] || {},
      );

      $link->set_from_related( q{%3$s}, $far_obj );

      $link->insert();

      $guard->commit if $guard;

      $far_obj;
EOC


    quote_sub "${class}::${set_meth}", sprintf( <<'EOC', $set_meth, $add_meth, $rel, $f_rel ), @extra_meth_qsub_args;

      my $self = shift;

      my $set_to = ( ref $_[0] eq 'ARRAY' )
        ? ( shift @_ )
        : do {
          $carp_unique->(
            "Calling '%1$s' with a list of items to link to is deprecated, use an arrayref instead"
          );

          # gobble up everything from @_ into a new arrayref
          [ splice @_ ]
        }
      ;

      # make sure folks are not invoking a bizarre mix of deprecated and curent syntax
      $self->throw_exception(
        "'%1$s' expects an arrayref of objects or hashrefs to link to, and an optional hashref of link data"
      ) if (
        @_ > 1
          or
        ( defined $_[0] and ref $_[0] ne 'HASH' )
      );

      my $guard;

      # there will only be a single delete() op, unless we have what to set to
      $guard = $self->result_source->schema->storage->txn_scope_guard
        if @$set_to;

      # if there is a where clause in the attributes, ensure we only delete
      # rows that are within the where restriction
      $self->related_resultset( q{%3$s} )
            ->search_rs(
              ( $rel_attrs->{where}
                ? ( $rel_attrs->{where}, { join => q{%4$s} } )
                : ()
              )
            )->delete;

      # add in the set rel objects
      $self->%2$s(
        $_,
        @_, # at this point @_ is either empty or contains a lone link-data hash
      ) for @$set_to;

      $guard->commit if $guard;
EOC


    # the last method needs no captures - just kill it all with fire
    $extra_meth_qsub_args[0] = {};


    quote_sub "${class}::${remove_meth}", sprintf( <<'EOC', $remove_meth, $rel, $f_rel ), @extra_meth_qsub_args;

      $_[0]->throw_exception("'%1$s' expects an object")
        unless defined Scalar::Util::blessed( $_[1] );

      $_[0]->related_resultset( q{%2$s} )
            ->search_rs( $_[1]->ident_condition( q{%3$s} ), { join => q{%3$s} } )
             ->delete;
EOC

}

1;
