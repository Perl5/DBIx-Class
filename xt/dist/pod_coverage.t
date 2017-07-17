BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => 'test_podcoverage';

use warnings;
use strict;

use Test::More;
use Module::Runtime 'require_module';
use lib 'maint/.Generated_Pod/lib';
use DBICTest;
use DBIx::Class::Schema::SanityChecker;
use namespace::clean;

# this has already been required but leave it here for CPANTS static analysis
require Test::Pod::Coverage;

# Since this is about checking documentation, a little documentation
# of what this is doing might be in order.
# The exceptions structure below is a hash keyed by the module
# name. Any * in a name is treated like a wildcard and will behave
# as expected. Modules are matched by longest string first, so
# A::B::C will match even if there is A::B*

# The value for each is a hash, which contains one or more
# (although currently more than one makes no sense) of the following
# things:-
#   skip   => a true value means this module is not checked
#   ignore => array ref containing list of methods which
#             do not need to be documented.
my $exceptions = {
    'DBIx::Class' => {
        ignore => [qw/
            component_base_class
        /]
    },
    'DBIx::Class::Optional::Dependencies' => {
        ignore => [qw/
            croak
        /]
    },
    'DBIx::Class::Carp' => {
        ignore => [qw/
            unimport
        /]
    },
    'DBIx::Class::Row' => {
        ignore => [qw/
            MULTICREATE_DEBUG
        /],
    },
    'DBIx::Class::FilterColumn' => {
        ignore => [qw/
            new
            update
            store_column
            get_column
            get_columns
            get_dirty_columns
            has_column_loaded
        /],
    },
    'DBIx::Class::ResultSource' => {
        ignore => [qw/
            compare_relationship_keys
            pk_depends_on
            resolve_condition
            resolve_join
            resolve_prefetch
            STORABLE_freeze
            STORABLE_thaw
            get_rsrc_instance_specific_attribute
            set_rsrc_instance_specific_attribute
            get_rsrc_instance_specific_handler
            set_rsrc_instance_specific_handler
        /],
    },
    'DBIx::Class::ResultSet' => {
        ignore => [qw/
            STORABLE_freeze
            STORABLE_thaw
        /],
    },
    'DBIx::Class::ResultSourceHandle' => {
        ignore => [qw/
            schema
            source_moniker
        /],
    },
    'DBIx::Class::Storage' => {
        ignore => [qw/
            schema
            cursor
        /]
    },
    'DBIx::Class::Schema' => {
        ignore => [qw/
            setup_connection_class
        /]
    },

    'DBIx::Class::Schema::Versioned' => {
        ignore => [ qw/
            connection
        /]
    },
    'DBIx::Class::Schema::SanityChecker' => {
        ignore => [ map {
          qr/^ (?: check_${_} | format_${_}_errors ) $/x
        } @{ DBIx::Class::Schema::SanityChecker->available_checks } ]
    },

    'DBIx::Class::Admin'        => {
        ignore => [ qw/
            BUILD
        /]
     },

    'DBIx::Class::Storage::DBI::Replicated*'        => {
        ignore => [ qw/
            connect_call_do_sql
            disconnect_call_do_sql
        /]
    },

    'DBIx::Class::_TempExtlib*'                     => { skip => 1 },

    'DBIx::Class::Admin::*'                         => { skip => 1 },
    'DBIx::Class::ClassResolver::PassThrough'       => { skip => 1 },
    'DBIx::Class::Componentised'                    => { skip => 1 },
    'DBIx::Class::AccessorGroup'                    => { skip => 1 },
    'DBIx::Class::Relationship::*'                  => { skip => 1 },
    'DBIx::Class::ResultSetProxy'                   => { skip => 1 },
    'DBIx::Class::ResultSourceProxy'                => { skip => 1 },
    'DBIx::Class::ResultSource::*'                  => { skip => 1 },
    'DBIx::Class::Storage::Statistics'              => { skip => 1 },
    'DBIx::Class::Storage::DBI::Replicated::Types'  => { skip => 1 },
    'DBIx::Class::GlobalDestruction'                => { skip => 1 },
    'DBIx::Class::Storage::BlockRunner'             => { skip => 1 }, # temporary

# test some specific components whose parents are exempt below
    'DBIx::Class::Relationship::Base'               => {},
    'DBIx::Class::SQLMaker::LimitDialects'          => {},

# internals
    'DBIx::Class::_Util'                            => { skip => 1 },
    'DBIx::Class::SQLMaker*'                        => { skip => 1 },
    'DBIx::Class::SQLAHacks*'                       => { skip => 1 },
    'DBIx::Class::Storage::DBI*'                    => { skip => 1 },
    'SQL::Translator::*'                            => { skip => 1 },

# deprecated / backcompat stuff
    'DBIx::Class::Serialize::Storable'              => { skip => 1 },
    'DBIx::Class::CDBICompat*'                      => { skip => 1 },
    'DBIx::Class::ResultSetManager'                 => { skip => 1 },
    'DBIx::Class::DB'                               => { skip => 1 },

# skipped because the synopsis covers it clearly
    'DBIx::Class::InflateColumn::File'              => { skip => 1 },

# internal subclass, nothing to POD
    'DBIx::Class::ResultSet::Pager'                 => { skip => 1 },
};

my $ex_lookup = {};
for my $string (keys %$exceptions) {
  my $ex = $exceptions->{$string};
  $string =~ s/\*/'.*?'/ge;
  my $re = qr/^$string$/;
  $ex_lookup->{$re} = $ex;
}

my @modules = sort { $a cmp $b } Test::Pod::Coverage::all_modules('lib');

foreach my $module (@modules) {
  SKIP: {

    my ($match) =
      grep { $module =~ $_ }
      (sort { length $b <=> length $a || $b cmp $a } (keys %$ex_lookup) )
    ;

    my $ex = $ex_lookup->{$match} if $match;

    skip ("$module exempt", 1) if ($ex->{skip});

    skip ("$module not loadable", 1) unless eval { require_module($module) };

    # build parms up from ignore list
    my $parms = {};
    $parms->{trustme} = [ map
      { ref $_ eq 'Regexp' ? $_ : qr/^\Q$_\E$/ }
      @{ $ex->{ignore} }
    ] if exists($ex->{ignore});

    # run the test with the potentially modified parm set
    Test::Pod::Coverage::pod_coverage_ok($module, $parms, "$module POD coverage");
  }
}

done_testing;
