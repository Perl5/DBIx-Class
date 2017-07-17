package # hide from PAUSE
    DBIx::Class::ResultSourceProxy;

use strict;
use warnings;

use base 'DBIx::Class';

# ! LOAD ORDER SENSITIVE !
# needs to be loaded early to query method attributes below
# and to do the around()s properly
use DBIx::Class::ResultSource;
my @wrap_rsrc_methods = qw(
  add_columns
  add_relationship
);

use DBIx::Class::_Util qw(
  quote_sub perlstring fail_on_internal_call describe_class_methods
);
use namespace::clean;

# FIXME: this is truly bizarre, not sure why it is this way since 93405cf0
# This value *IS* *DIFFERENT* from source_name in the underlying rsrc
# instance, and there is *ZERO EFFORT* made to synchronize them...
# FIXME: Due to the above marking this as a rsrc_proxy method is also out
# of the question...
# FIXME: this used to be a sub-type of inherited ( to see run:
# `git log -Sinherited_ro_instance lib/DBIx/Class/ResultSourceProxy.pm` )
# however given the lack of any sync effort as described above *anyway*,
# it makes no sense to guard for erroneous use at a non-trivial cost in
# performance (and may end up in the way of future optimizations as per
# https://github.com/vovkasm/Class-Accessor-Inherited-XS/issues/2#issuecomment-243246924 )
__PACKAGE__->mk_group_accessors( inherited => 'source_name');

# The marking with indirect_sugar will cause warnings to be issued in darkpan code
# (though extremely unlikely)
sub get_inherited_ro_instance :DBIC_method_is_indirect_sugar {
  DBIx::Class::Exception->throw(
    "The 'inherted_ro_instance' CAG group has been retired - use 'inherited' instead"
  );
}
sub set_inherited_ro_instance :DBIC_method_is_indirect_sugar {
  DBIx::Class::Exception->throw(
    "The 'inherted_ro_instance' CAG group has been retired - use 'inherited' instead"
  );
}

sub add_columns :DBIC_method_is_bypassable_resultsource_proxy {
  my ($class, @cols) = @_;
  my $source = $class->result_source;
  local $source->{__callstack_includes_rsrc_proxy_method} = "add_columns";

  $source->add_columns(@cols);

  my $colinfos;
  foreach my $c (grep { !ref } @cols) {
    # If this is an augment definition get the real colname.
    $c =~ s/^\+//;

    $class->register_column(
      $c,
      ( $colinfos ||= $source->columns_info )->{$c}
    );
  }
}

sub add_column :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->add_columns(@_)
}

sub add_relationship :DBIC_method_is_bypassable_resultsource_proxy {
  my ($class, $rel, @rest) = @_;
  my $source = $class->result_source;
  local $source->{__callstack_includes_rsrc_proxy_method} = "add_relationship";

  $source->add_relationship($rel => @rest);
  $class->register_relationship($rel => $source->relationship_info($rel));
}


# legacy resultset_class accessor, seems to be used by cdbi only
sub iterator_class :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  shift->result_source->resultset_class(@_)
}

for my $method_to_proxy (qw/
  source_info
  result_class
  resultset_class
  resultset_attributes

  columns
  has_column

  remove_column
  remove_columns

  column_info
  columns_info
  column_info_from_storage

  set_primary_key
  primary_columns
  sequence

  add_unique_constraint
  add_unique_constraints

  unique_constraints
  unique_constraint_names
  unique_constraint_columns

  relationships
  relationship_info
  has_relationship
/) {
  my $qsub_opts = { attributes => [
    do {
      no strict 'refs';
      attributes::get( \&{"DBIx::Class::ResultSource::$method_to_proxy"} );
    }
  ] };

  # bypassable default for backcompat, except for indirect methods
  # ( those will simply warn during the sanheck )
  if(! grep
    { $_ eq 'DBIC_method_is_indirect_sugar' }
    @{ $qsub_opts->{attributes} }
  ) {
    push @wrap_rsrc_methods, $method_to_proxy;
    push @{ $qsub_opts->{atributes} }, 'DBIC_method_is_bypassable_resultsource_proxy';
  }

  quote_sub __PACKAGE__."::$method_to_proxy", sprintf( <<'EOC', $method_to_proxy ), {}, $qsub_opts;
    DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and DBIx::Class::_Util::fail_on_internal_call;

    my $rsrc = shift->result_source;
    local $rsrc->{__callstack_includes_rsrc_proxy_method} = q(%1$s);
    $rsrc->%1$s (@_);
EOC

}

# This is where the "magic" of detecting/invoking the proper overridden
# Result method takes place. It isn't implemented as a stateless out-of-band
# SanityCheck as invocation requires certain state in the $rsrc object itself
# in order not to loop over itself. It is not in ResultSource.pm either
# because of load order and because the entire stack is just terrible :/
#
# The code is not easily readable, as it it optimized for execution time
# (this stuff will be run all the time across the entire install base :/ )
#
{
  our %__rsrc_proxy_meta_cache;

  sub DBIx::Class::__RsrcProxy_iThreads_handler__::CLONE {
    # recreating this cache is pretty cheap: just blow it away
    %__rsrc_proxy_meta_cache = ();
  }

  for my $method_to_wrap (@wrap_rsrc_methods) {

    my @src_args = (
      perlstring $method_to_wrap,
    );

    my $orig = do {
      no strict 'refs';
      \&{"DBIx::Class::ResultSource::$method_to_wrap"}
    };

    my %unclassified_override_warn_emitted;

    my @qsub_args = (
      {
        # ref to hashref, this is how S::Q works
        '$rsrc_proxy_meta_cache' => \\%__rsrc_proxy_meta_cache,
        '$unclassified_override_warn_emitted' => \\%unclassified_override_warn_emitted,
        '$orig' => \$orig,
      },
      { attributes => [ attributes::get($orig) ] }
    );

    quote_sub "DBIx::Class::ResultSource::$method_to_wrap", sprintf( <<'EOC', @src_args ), @qsub_args;

      my $overridden_proxy_cref;

      # fall through except when...
      return &$orig unless (

        # FIXME - this may be necessary some day, but skip the hit for now
        # Scalar::Util::reftype $_[0] eq 'HASH'
        #   and

        # there is a class to check in the first place
        defined $_[0]->{result_class}

          and
        # we are not in a reinvoked callstack
        (
          ( $_[0]->{__callstack_includes_rsrc_proxy_method} || '' )
            ne
          %1$s
        )

          and
        # there is a proxied method in the first place
        (
          ( $rsrc_proxy_meta_cache->{address}{%1$s} ||= 0 + (
            DBIx::Class::ResultSourceProxy->can(%1$s)
              ||
            -1
          ) )
            >
          0
        )

          and
        # the proxied method *is overridden*
        (
          $rsrc_proxy_meta_cache->{address}{%1$s}
            !=
          # the can() should not be able to fail in theory, but the
          # result class may not inherit from ::Core *at all*
          # hence we simply ||ourselves to paper over this eventuality
          (
            ( $overridden_proxy_cref = $_[0]->{result_class}->can(%1$s) )
              ||
            $rsrc_proxy_meta_cache->{address}{%1$s}
          )
        )

          and
        # no short-circuiting atributes
        (! grep
          {
            # checking that:
            #
            # - Override is not something DBIC plastered on top of things
            #   One would think this is crazy, yet there it is... sigh:
            #   https://metacpan.org/source/KARMAN/DBIx-Class-RDBOHelpers-0.12/t/lib/MyDBIC/Schema/Cd.pm#L26-27
            #
            # - And is not an m2m crapfest
            #
            # - And is not something marked as bypassable

            $_ =~ / ^ DBIC_method_is_ (?:
              generated_from_resultsource_metadata
                |
              m2m_ (?: extra_)? sugar (?:_with_attrs)?
                |
              bypassable_resultsource_proxy
            ) $ /x
          }
          keys %%{ $rsrc_proxy_meta_cache->{attrs}{$overridden_proxy_cref} ||= {
            map { $_ => 1 } attributes::get($overridden_proxy_cref)
          }}
        )
      );

      # Getting this far means that there *is* an override
      # and it is *not* marked for a skip

      # we were asked to loop back through the Result override
      if (
        $rsrc_proxy_meta_cache->{attrs}
                                 {$overridden_proxy_cref}
                                  {DBIC_method_is_mandatory_resultsource_proxy}
      ) {
        local $_[0]->{__callstack_includes_rsrc_proxy_method} = %1$s;

        # replace $self without compromising aliasing
        splice @_, 0, 1, $_[0]->{result_class};

        return &$overridden_proxy_cref;
      }
      # complain (sparsely) and carry on
      else {

        # FIXME!!! - terrible, need to swap for something saner later
        my ($cs) = DBIx::Class::Carp::__find_caller( __PACKAGE__ );

        my $key = $cs . $overridden_proxy_cref;

        unless( $unclassified_override_warn_emitted->{$key} ) {

          # find the real origin
          my @meth_stack = @{ DBIx::Class::_Util::describe_class_methods(
            ref $_[0]->{result_class} || $_[0]->{result_class}
          )->{methods}{%1$s} };

          my $in_class = (shift @meth_stack)->{via_class};

          my $possible_supers;
          while (
            @meth_stack
              and
            $meth_stack[0]{via_class} ne __PACKAGE__
          ) {
            push @$possible_supers, (shift @meth_stack)->{via_class};
          }

          $possible_supers = $possible_supers
            ? sprintf(
              ' ( and possible SUPERs: %%s )',
              join ', ', map
                { join '::', $_, %1$s }
                @$possible_supers
            )
            : ''
          ;

          my $fqmeth = $in_class . '::' . %1$s . '()';

          DBIx::Class::_Util::emit_loud_diag(

            # Repurpose the assertion envvar ( the override-check is independent
            # from the schema san-checker, but the spirit is the same )
            confess => $ENV{DBIC_ASSERT_NO_FAILING_SANITY_CHECKS},

            msg =>
              "The override method $fqmeth$possible_supers has been bypassed "
            . "$cs\n"
            . "In order to silence this warning you must tag the "
            . "definition of $fqmeth with one of the attributes "
            . "':DBIC_method_is_bypassable_resultsource_proxy' or "
            . "':DBIC_method_is_mandatory_resultsource_proxy' ( see "
            . "https://is.gd/dbic_rsrcproxy_methodattr for more info )\n"
          );

          # only set if we didn't throw
          $unclassified_override_warn_emitted->{$key} = 1;
        }

        return &$orig;
      }
EOC

  }

  Class::C3->reinitialize() if DBIx::Class::_ENV_::OLD_MRO;
}

# CI sanity check that all annotations make sense
if(
  DBIx::Class::_ENV_::ASSERT_NO_ERRONEOUS_METAINSTANCE_USE
    and
  # no point taxing 5.8 with this
  ! DBIx::Class::_ENV_::OLD_MRO
) {

  my ( $rsrc_methods, $rsrc_proxy_methods, $base_methods ) = map {
    describe_class_methods($_)->{methods}
  } qw(
    DBIx::Class::ResultSource
    DBIx::Class::ResultSourceProxy
    DBIx::Class
  );

  delete $rsrc_methods->{$_}, delete $rsrc_proxy_methods->{$_}
    for keys %$base_methods;

  (
    $rsrc_methods->{$_}
      and
    ! $rsrc_proxy_methods->{$_}[0]{attributes}{DBIC_method_is_indirect_sugar}
  )
    or
  delete $rsrc_proxy_methods->{$_}
    for keys %$rsrc_proxy_methods;

  # see fat FIXME at top of file
  delete @{$rsrc_proxy_methods}{qw( source_name _source_name_accessor )};

  if (
    ( my $proxied = join "\n", map "\t$_", sort keys %$rsrc_proxy_methods )
      ne
    ( my $wrapped = join "\n", map "\t$_", sort @wrap_rsrc_methods )
  ) {
    Carp::confess(
      "Unexpected mismatch between the list of proxied methods:\n\n$proxied"
    . "\n\nand the list of wrapped rsrc methods:\n\n$wrapped\n\n"
    );
  }
}

1;
