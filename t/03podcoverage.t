use Test::More;
use List::Util ();

eval "use Pod::Coverage 0.19";
plan skip_all => 'Pod::Coverage 0.19 required' if $@;
eval "use Test::Pod::Coverage 1.04";
plan skip_all => 'Test::Pod::Coverage 1.04 required' if $@;

plan skip_all => 'set TEST_POD to enable this test'
  unless ($ENV{TEST_POD} || -e 'MANIFEST.SKIP');


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
            MODIFY_CODE_ATTRIBUTES
            component_base_class
            mk_classdata
            mk_classaccessor
        /]
    },
    'DBIx::Class::Row' => {
        ignore => [qw/
            MULTICREATE_DEBUG
        /],
    },
    'DBIx::Class::ResultSource' => {
        ignore => [qw/
            compare_relationship_keys
            pk_depends_on
            resolve_condition
            resolve_join
            resolve_prefetch
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

    'DBIx::Class::ClassResolver::PassThrough'       => { skip => 1 },
    'DBIx::Class::Componentised'                    => { skip => 1 },
    'DBIx::Class::Relationship::*'                  => { skip => 1 },
    'DBIx::Class::ResultSetProxy'                   => { skip => 1 },
    'DBIx::Class::ResultSourceProxy'                => { skip => 1 },
    'DBIx::Class::Storage::Statistics'              => { skip => 1 },

# test some specific components whose parents are exempt below
    'DBIx::Class::Storage::DBI::Replicated*'        => {},
    'DBIx::Class::Relationship::Base'               => {},

# internals
    'DBIx::Class::SQLAHacks*'                       => { skip => 1 },
    'DBIx::Class::Storage::DBI*'                    => { skip => 1 },
    'SQL::Translator::*'                            => { skip => 1 },

# deprecated / backcompat stuff
    'DBIx::Class::CDBICompat*'                      => { skip => 1 },
    'DBIx::Class::ResultSetManager'                 => { skip => 1 },
    'DBIx::Class::DB'                               => { skip => 1 },

# skipped because the synopsis covers it clearly
    'DBIx::Class::InflateColumn::File'              => { skip => 1 },
};

my $ex_lookup = {};
for my $string (keys %$exceptions) {
  my $ex = $exceptions->{$string};
  $string =~ s/\*/'.*?'/ge;
  my $re = qr/^$string$/;
  $ex_lookup->{$re} = $ex;
}

my @modules = sort { $a cmp $b } (Test::Pod::Coverage::all_modules());

foreach my $module (@modules) {
  SKIP: {

    my ($match) = List::Util::first
      { $module =~ $_ }
      (sort { length $b <=> length $a || $b cmp $a } (keys %$ex_lookup) )
    ;

    my $ex = $ex_lookup->{$match} if $match;

    skip ("$module exempt", 1) if ($ex->{skip});

    # build parms up from ignore list
    my $parms = {};
    $parms->{trustme} =
      [ map { qr/^$_$/ } @{ $ex->{ignore} } ]
        if exists($ex->{ignore});

    # run the test with the potentially modified parm set
    pod_coverage_ok($module, $parms, "$module POD coverage");
  }
}

done_testing;
