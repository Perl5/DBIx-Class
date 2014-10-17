package DBIx::Class::Optional::Dependencies;

### This may look crazy, but it in fact tangibly ( by 50(!)% ) shortens
#   the skip-test time when everything requested is unavailable
use if $ENV{RELEASE_TESTING} => 'warnings';
use if $ENV{RELEASE_TESTING} => 'strict';

sub croak {
  require Carp;
  Carp::croak(@_);
};
###

# NO EXTERNAL NON-5.8.1 CORE DEPENDENCIES EVER (e.g. C::A::G)
# This module is to be loaded by Makefile.PM on a pristine system

# POD is generated automatically by calling _gen_pod from the
# Makefile.PL in $AUTHOR mode

# NOTE: the rationale for 2 JSON::Any versions is that
# we need the newer only to work around JSON::XS, which
# itself is an optional dep
my $min_json_any = {
  'JSON::Any'                     => '1.23',
};
my $test_and_dist_json_any = {
  'JSON::Any'                     => '1.31',
};

my $moose_basic = {
  'Moose'                         => '0.98',
  'MooseX::Types'                 => '0.21',
  'MooseX::Types::LoadableClass'  => '0.011',
};

my $dbic_reqs = {
  replicated => {
    req => $moose_basic,
    pod => {
      title => 'Storage::Replicated',
      desc => 'Modules required for L<DBIx::Class::Storage::DBI::Replicated>',
    },
  },

  test_replicated => {
    include => 'replicated',
    req => {
      'Test::Moose' => '0',
    },
  },

  admin => {
    req => {
      %$moose_basic,
      %$min_json_any,
      'MooseX::Types::Path::Class' => '0.05',
      'MooseX::Types::JSON' => '0.02',
    },
    pod => {
      title => 'DBIx::Class::Admin',
      desc => 'Modules required for the DBIx::Class administrative library',
    },
  },

  admin_script => {
    include => 'admin',
    req => {
      'Getopt::Long::Descriptive' => '0.081',
      'Text::CSV' => '1.16',
    },
    pod => {
      title => 'dbicadmin',
      desc => 'Modules required for the CLI DBIx::Class interface dbicadmin',
    },
  },

  deploy => {
    req => {
      'SQL::Translator'           => '0.11018',
    },
    pod => {
      title => 'Storage::DBI::deploy()',
      desc => 'Modules required for L<DBIx::Class::Storage::DBI/deployment_statements> and L<DBIx::Class::Schema/deploy>',
    },
  },

  id_shortener => {
    req => {
      'Math::BigInt' => '1.80',
      'Math::Base36' => '0.07',
    },
  },

  test_component_accessor => {
    req => {
      'Class::Unload'             => '0.07',
    },
  },

  test_pod => {
    req => {
      'Test::Pod'                 => '1.42',
    },
    release_testing_mandatory => 1,
  },

  test_podcoverage => {
    req => {
      'Test::Pod::Coverage'       => '1.08',
      'Pod::Coverage'             => '0.20',
    },
    release_testing_mandatory => 1,
  },

  test_whitespace => {
    req => {
      'Test::EOL'                 => '1.0',
      'Test::NoTabs'              => '0.9',
    },
    release_testing_mandatory => 1,
  },

  test_strictures => {
    req => {
      'Test::Strict'              => '0.20',
    },
    release_testing_mandatory => 1,
  },

  test_prettydebug => {
    req => $min_json_any,
  },

  test_admin_script => {
    include => 'admin_script',
    req => {
      %$test_and_dist_json_any,
      'JSON' => 0,
      'JSON::PP' => 0,
      'Cpanel::JSON::XS' => 0,
      'JSON::XS' => 0,
      $^O eq 'MSWin32'
        # for t/admin/10script.t
        ? ('Win32::ShellQuote' => 0)
        # DWIW does not compile (./configure even) on win32
        : ('JSON::DWIW' => 0 )
      ,
    }
  },

  test_leaks_heavy => {
    req => {
      'Class::MethodCache' => '0.02',
      'PadWalker' => '1.06',
    },
  },

  test_dt => {
    req => {
      'DateTime'                    => '0.55',
      'DateTime::Format::Strptime'  => '1.2',
    },
  },

  test_dt_sqlite => {
    include => 'test_dt',
    req => {
      # t/36datetime.t
      # t/60core.t
      'DateTime::Format::SQLite'  => '0',
    },
  },

  test_dt_mysql => {
    include => 'test_dt',
    req => {
      # t/inflate/datetime_mysql.t
      # (doesn't need Mysql itself)
      'DateTime::Format::MySQL'   => '0',
    },
  },

  test_dt_pg => {
    include => 'test_dt',
    req => {
      # t/inflate/datetime_pg.t
      # (doesn't need PG itself)
      'DateTime::Format::Pg'      => '0.16004',
    },
  },

  test_cdbicompat => {
    include => 'test_dt',
    req => {
      'Class::DBI::Plugin::DeepAbstractSearch' => '0',
      'Time::Piece::MySQL'        => '0',
      'Date::Simple'              => '3.03',
    },
  },

  rdbms_generic_odbc => {
    req => {
      'DBD::ODBC' => 0,
    }
  },

  rdbms_generic_ado => {
    req => {
      'DBD::ADO' => 0,
    }
  },

  # this is just for completeness as SQLite
  # is a core dep of DBIC for testing
  rdbms_sqlite => {
    req => {
      'DBD::SQLite' => 0,
    },
    pod => {
      title => 'SQLite support',
      desc => 'Modules required to connect to SQLite',
    },
  },

  rdbms_pg => {
    req => {
      # when changing this list make sure to adjust xt/optional_deps.t
      'DBD::Pg' => 0,
    },
    pod => {
      title => 'PostgreSQL support',
      desc => 'Modules required to connect to PostgreSQL',
    },
  },

  rdbms_mssql_odbc => {
    include => 'rdbms_generic_odbc',
    pod => {
      title => 'MSSQL support via DBD::ODBC',
      desc => 'Modules required to connect to MSSQL via DBD::ODBC',
    },
  },

  rdbms_mssql_sybase => {
    req => {
      'DBD::Sybase' => 0,
    },
    pod => {
      title => 'MSSQL support via DBD::Sybase',
      desc => 'Modules required to connect to MSSQL via DBD::Sybase',
    },
  },

  rdbms_mssql_ado => {
    include => 'rdbms_generic_ado',
    pod => {
      title => 'MSSQL support via DBD::ADO (Windows only)',
      desc => 'Modules required to connect to MSSQL via DBD::ADO. This particular DBD is available on Windows only',
    },
  },

  rdbms_msaccess_odbc => {
    include => 'rdbms_generic_odbc',
    pod => {
      title => 'MS Access support via DBD::ODBC',
      desc => 'Modules required to connect to MS Access via DBD::ODBC',
    },
  },

  rdbms_msaccess_ado => {
    include => 'rdbms_generic_ado',
    pod => {
      title => 'MS Access support via DBD::ADO (Windows only)',
      desc => 'Modules required to connect to MS Access via DBD::ADO. This particular DBD is available on Windows only',
    },
  },

  rdbms_mysql => {
    req => {
      'DBD::mysql' => 0,
    },
    pod => {
      title => 'MySQL support',
      desc => 'Modules required to connect to MySQL',
    },
  },

  rdbms_oracle => {
    include => 'id_shortener',
    req => {
      'DBD::Oracle' => 0,
    },
    pod => {
      title => 'Oracle support',
      desc => 'Modules required to connect to Oracle',
    },
  },

  rdbms_ase => {
    req => {
      'DBD::Sybase' => 0,
    },
    pod => {
      title => 'Sybase ASE support',
      desc => 'Modules required to connect to Sybase ASE',
    },
  },

  rdbms_db2 => {
    req => {
      'DBD::DB2' => 0,
    },
    pod => {
      title => 'DB2 support',
      desc => 'Modules required to connect to DB2',
    },
  },

  rdbms_db2_400 => {
    include => 'rdbms_generic_odbc',
    pod => {
      title => 'DB2 on AS/400 support',
      desc => 'Modules required to connect to DB2 on AS/400',
    },
  },

  rdbms_informix => {
    req => {
      'DBD::Informix' => 0,
    },
    pod => {
      title => 'Informix support',
      desc => 'Modules required to connect to Informix',
    },
  },

  rdbms_sqlanywhere => {
    req => {
      'DBD::SQLAnywhere' => 0,
    },
    pod => {
      title => 'SQLAnywhere support',
      desc => 'Modules required to connect to SQLAnywhere',
    },
  },

  rdbms_sqlanywhere_odbc => {
    include => 'rdbms_generic_odbc',
    pod => {
      title => 'SQLAnywhere support via DBD::ODBC',
      desc => 'Modules required to connect to SQLAnywhere via DBD::ODBC',
    },
  },

  rdbms_firebird => {
    req => {
      'DBD::Firebird' => 0,
    },
    pod => {
      title => 'Firebird support',
      desc => 'Modules required to connect to Firebird',
    },
  },

  rdbms_firebird_interbase => {
    req => {
      'DBD::InterBase' => 0,
    },
    pod => {
      title => 'Firebird support via DBD::InterBase',
      desc => 'Modules required to connect to Firebird via DBD::InterBase',
    },
  },

  rdbms_firebird_odbc => {
    include => 'rdbms_generic_odbc',
    pod => {
      title => 'Firebird support via DBD::ODBC',
      desc => 'Modules required to connect to Firebird via DBD::ODBC',
    },
  },

  test_rdbms_pg => {
    include => 'rdbms_pg',
    env => [
      DBICTEST_PG_DSN => 1,
      DBICTEST_PG_USER => 0,
      DBICTEST_PG_PASS => 0,
    ],
    req => {
      # the order does matter because the rdbms support group might require
      # a different version that the test group
      #
      # when changing this list make sure to adjust xt/optional_deps.t
      'DBD::Pg' => '2.009002',  # specific version to test bytea
    },
  },

  test_rdbms_mssql_odbc => {
    include => 'rdbms_mssql_odbc',
    env => [
      DBICTEST_MSSQL_ODBC_DSN => 1,
      DBICTEST_MSSQL_ODBC_USER => 0,
      DBICTEST_MSSQL_ODBC_PASS => 0,
    ],
  },

  test_rdbms_mssql_ado => {
    include => 'rdbms_mssql_ado',
    env => [
      DBICTEST_MSSQL_ADO_DSN => 1,
      DBICTEST_MSSQL_ADO_USER => 0,
      DBICTEST_MSSQL_ADO_PASS => 0,
    ],
  },

  test_rdbms_mssql_sybase => {
    include => 'rdbms_mssql_sybase',
    env => [
      DBICTEST_MSSQL_DSN => 1,
      DBICTEST_MSSQL_USER => 0,
      DBICTEST_MSSQL_PASS => 0,
    ],
  },

  test_rdbms_msaccess_odbc => {
    include => [qw(rdbms_msaccess_odbc test_dt)],
    env => [
      DBICTEST_MSACCESS_ODBC_DSN => 1,
      DBICTEST_MSACCESS_ODBC_USER => 0,
      DBICTEST_MSACCESS_ODBC_PASS => 0,
    ],
    req => {
      'Data::GUID' => '0',
    },
  },

  test_rdbms_msaccess_ado => {
    include => [qw(rdbms_msaccess_ado test_dt)],
    env => [
      DBICTEST_MSACCESS_ADO_DSN => 1,
      DBICTEST_MSACCESS_ADO_USER => 0,
      DBICTEST_MSACCESS_ADO_PASS => 0,
    ],
    req => {
      'Data::GUID' => 0,
    },
  },

  test_rdbms_mysql => {
    include => 'rdbms_mysql',
    env => [
      DBICTEST_MYSQL_DSN => 1,
      DBICTEST_MYSQL_USER => 0,
      DBICTEST_MYSQL_PASS => 0,
    ],
  },

  test_rdbms_oracle => {
    include => 'rdbms_oracle',
    env => [
      DBICTEST_ORA_DSN => 1,
      DBICTEST_ORA_USER => 0,
      DBICTEST_ORA_PASS => 0,
    ],
    req => {
      'DateTime::Format::Oracle' => '0',
      'DBD::Oracle'              => '1.24',
    },
  },

  test_rdbms_ase => {
    include => 'rdbms_ase',
    env => [
      DBICTEST_SYBASE_DSN => 1,
      DBICTEST_SYBASE_USER => 0,
      DBICTEST_SYBASE_PASS => 0,
    ],
  },

  test_rdbms_db2 => {
    include => 'rdbms_db2',
    env => [
      DBICTEST_DB2_DSN => 1,
      DBICTEST_DB2_USER => 0,
      DBICTEST_DB2_PASS => 0,
    ],
  },

  test_rdbms_db2_400 => {
    include => 'rdbms_db2_400',
    env => [
      DBICTEST_DB2_400_DSN => 1,
      DBICTEST_DB2_400_USER => 0,
      DBICTEST_DB2_400_PASS => 0,
    ],
  },

  test_rdbms_informix => {
    include => 'rdbms_informix',
    env => [
      DBICTEST_INFORMIX_DSN => 1,
      DBICTEST_INFORMIX_USER => 0,
      DBICTEST_INFORMIX_PASS => 0,
    ],
  },

  test_rdbms_sqlanywhere => {
    include => 'rdbms_sqlanywhere',
    env => [
      DBICTEST_SQLANYWHERE_DSN => 1,
      DBICTEST_SQLANYWHERE_USER => 0,
      DBICTEST_SQLANYWHERE_PASS => 0,
    ],
  },

  test_rdbms_sqlanywhere_odbc => {
    include => 'rdbms_sqlanywhere_odbc',
    env => [
      DBICTEST_SQLANYWHERE_ODBC_DSN => 1,
      DBICTEST_SQLANYWHERE_ODBC_USER => 0,
      DBICTEST_SQLANYWHERE_ODBC_PASS => 0,
    ],
  },

  test_rdbms_firebird => {
    include => 'rdbms_firebird',
    env => [
      DBICTEST_FIREBIRD_DSN => 1,
      DBICTEST_FIREBIRD_USER => 0,
      DBICTEST_FIREBIRD_PASS => 0,
    ],
  },

  test_rdbms_firebird_interbase => {
    include => 'rdbms_firebird_interbase',
    env => [
      DBICTEST_FIREBIRD_INTERBASE_DSN => 1,
      DBICTEST_FIREBIRD_INTERBASE_USER => 0,
      DBICTEST_FIREBIRD_INTERBASE_PASS => 0,
    ],
  },

  test_rdbms_firebird_odbc => {
    include => 'rdbms_firebird_odbc',
    env => [
      DBICTEST_FIREBIRD_ODBC_DSN => 1,
      DBICTEST_FIREBIRD_ODBC_USER => 0,
      DBICTEST_FIREBIRD_ODBC_PASS => 0,
    ],
  },

  test_memcached => {
    env => [
      DBICTEST_MEMCACHED => 1,
    ],
    req => {
      'Cache::Memcached' => 0,
    },
  },

  dist_dir => {
    req => {
      %$test_and_dist_json_any,
      'ExtUtils::MakeMaker' => '6.64',
      'Pod::Inherit'        => '0.91',
    },
  },

  dist_upload => {
    req => {
      'CPAN::Uploader' => '0.103001',
    },
  },
};



### Public API

sub import {
  my $class = shift;

  if (@_) {

    my $action = shift;

    if ($action eq '-die_without') {
      my $err;
      {
        local $@;
        eval { $class->die_unless_req_ok_for(\@_); 1 }
          or $err = $@;
      }
      die "\n$err\n" if $err;
    }
    elsif ($action eq '-list_missing') {
      print $class->modreq_missing_for(\@_);
      print "\n";
      exit 0;
    }
    elsif ($action eq '-skip_all_without') {

      # sanity check - make sure ->current_test is 0 and no plan has been declared
      do {
        local $@;
        defined eval {
          Test::Builder->new->current_test
            or
          Test::Builder->new->has_plan
        };
      } and croak("Unable to invoke -skip_all_without after testing has started");

      if ( my $missing = $class->req_missing_for(\@_) ) {

        die ("\nMandatory requirements not satisfied during release-testing: $missing\n\n")
          if $ENV{RELEASE_TESTING} and $class->_groups_to_reqs(\@_)->{release_testing_mandatory};

        print "1..0 # SKIP requirements not satisfied: $missing\n";
        exit 0;
      }
    }
    elsif ($action =~ /^-/) {
      croak "Unknown import-time action '$action'";
    }
    else {
      croak "$class is not an exporter, unable to import '$action'";
    }
  }

  1;
}

sub unimport {
  croak( __PACKAGE__ . " does not implement unimport" );
}

# OO for (mistakenly considered) ease of extensibility, not due to any need to
# carry state of any sort. This API is currently used outside, so leave as-is.
# FIXME - make sure to not propagate this further if module is extracted as a
# standalone library - keep the stupidity to a DBIC-secific shim!
#
sub req_list_for {
  shift->_groups_to_reqs(@_)->{effective_modreqs};
}

sub modreq_list_for {
  shift->_groups_to_reqs(@_)->{modreqs};
}

sub req_group_list {
  +{ map
    { $_ => $_[0]->_groups_to_reqs($_) }
    keys %$dbic_reqs
  }
}

sub req_errorlist_for { shift->modreq_errorlist_for(@_) }  # deprecated
sub modreq_errorlist_for {
  my $self = shift;
  $self->_errorlist_for_modreqs( $self->_groups_to_reqs(@_)->{modreqs} );
}

sub req_ok_for {
  shift->req_missing_for(@_) ? 0 : 1;
}

sub req_missing_for {
  my $self = shift;

  my $reqs = $self->_groups_to_reqs(@_);
  my $mods_missing = $self->modreq_missing_for(@_);

  return '' if
    ! $mods_missing
      and
    ! $reqs->{missing_envvars}
  ;

  my @res = $mods_missing || ();

  push @res, 'the following group(s) of environment variables: ' . join ' and ', map
    { __envvar_group_desc($_) }
    @{$reqs->{missing_envvars}}
  if $reqs->{missing_envvars};

  return (
    ( join ' as well as ', @res )
      .
    ( $reqs->{modreqs_fully_documented} ? " (see @{[ ref $self || $self ]} documentation for details)" : '' ),
  );
}

sub modreq_missing_for {
  my $self = shift;

  my $reqs = $self->_groups_to_reqs(@_);
  my $modreq_errors = $self->_errorlist_for_modreqs($reqs->{modreqs})
    or return '';

  join ' ', map
    { $reqs->{modreqs}{$_} ? qq("$_~>=$reqs->{modreqs}{$_}") : $_ }
    sort { lc($a) cmp lc($b) } keys %$modreq_errors
  ;
}

sub die_unless_req_ok_for {
  if (my $err = shift->req_missing_for(@_) ) {
    die "Unable to continue due to missing requirements: $err\n";
  }
}



### Private functions

# potentially shorten group desc
sub __envvar_group_desc {
  my @envs = @{$_[0]};

  my (@res, $last_prefix);
  while (my $ev = shift @envs) {
    my ($pref, $sep, $suff) = split / ([\_\-]) (?= [^\_\-]+ \z )/x, $ev;

    if ( defined $sep and ($last_prefix||'') eq $pref ) {
        push @res, "...${sep}${suff}"
    }
    else {
      push @res, $ev;
    }

    $last_prefix = $pref if $sep;
  }

  join '/', @res;
}



### Private OO API
our %req_unavailability_cache;

# this method is just a lister and envvar/metadata checker - it does not try to load anything
my $processed_groups = {};
sub _groups_to_reqs {
  my ($self, $groups) = @_;

  $groups = [ $groups || () ]
    unless ref $groups eq 'ARRAY';

  croak "@{[ (caller(1))[3] ]}() expects a requirement group name or arrayref of group names"
    unless @$groups;

  my $ret = {
    modreqs => {},
    modreqs_fully_documented => 1,
  };

  for my $group ( grep { ! $processed_groups->{$_} } @$groups ) {

    $group =~ /\A [A-Za-z][0-9A-Z_a-z]* \z/x
      or croak "Invalid requirement group name '$group': only ascii alphanumerics and _ are allowed";

    croak "Requirement group '$group' is not defined" unless defined $dbic_reqs->{$group};

    my $group_reqs = $dbic_reqs->{$group}{req};

    # sanity-check
    for (keys %$group_reqs) {

      $_ =~ /\A [A-Z_a-z][0-9A-Z_a-z]* (?:::[0-9A-Z_a-z]+)* \z /x
        or croak "Requirement '$_' in group '$group' is not a valid module name";

      # !!!DO NOT CHANGE!!!
      # remember - version.pm may not be available on the system
      croak "Requirement '$_' in group '$group' specifies an invalid version '$group_reqs->{$_}' (only plain non-underscored floating point decimals are supported)"
        if ( ($group_reqs->{$_}||0) !~ / \A [0-9]+ (?: \. [0-9]+ )? \z /x );
    }

    # check if we have all required envvars if such names are defined
    my ($some_envs_required, $some_envs_missing);
    if (my @e = @{$dbic_reqs->{$group}{env} || [] }) {

      croak "Unexpected 'env' attribute under group '$group' (only allowed in test_* groups)"
        unless $group =~ /^test_/;

      croak "Unexpected *odd* list in 'env' under group '$group'"
        if @e % 2;

      my @group_envnames_list;

      # deconstruct the whole thing
      while (@e) {
        push @group_envnames_list, my $envname = shift @e;

        # env required or not
        next unless shift @e;

        $some_envs_required ||= 1;

        $some_envs_missing ||= (
          ! defined $ENV{$envname}
            or
          ! length $ENV{$envname}
        );
      }

      croak "None of the envvars in group '$group' declared as required, making the requirement moot"
        unless $some_envs_required;

      push @{$ret->{missing_envvars}}, \@group_envnames_list if $some_envs_missing;
    }

    # get the reqs for includes if any
    my $inc_reqs;
    if (my $incs = $dbic_reqs->{$group}{include}) {
      $incs = [ $incs ] unless ref $incs eq 'ARRAY';

      croak "Malformed 'include' for group '$group': must be another existing group name or arrayref of existing group names"
        unless @$incs;

      local $processed_groups->{$group} = 1;

      my $subreqs = $self->_groups_to_reqs($incs);

      croak "Includes with variable effective_modreqs not yet supported"
        if $subreqs->{effective_modreqs_differ};

      $inc_reqs = $subreqs->{modreqs};

    }

    # assemble into the final ret
    for my $type (
      'modreqs',
      $some_envs_missing ? () : 'effective_modreqs'
    ) {
      for my $req_bag ($group_reqs, $inc_reqs||()) {
        for my $mod (keys %$req_bag) {

          $ret->{$type}{$mod} = $req_bag->{$mod}||0 if (

            ! exists $ret->{$type}{$mod}
              or
            # we sanitized the version to be numeric above - we can just -gt it
            ($req_bag->{$mod}||0) > $ret->{$type}{$mod}

          );
        }
      }
    }

    $ret->{effective_modreqs_differ} ||= !!$some_envs_missing;

    $ret->{modreqs_fully_documented} &&= !!$dbic_reqs->{$group}{pod};

    $ret->{release_testing_mandatory} ||= !!$dbic_reqs->{$group}{release_testing_mandatory};
  }

  return $ret;
}


# this method tries to load specified modreqs and returns a hashref of
# module/loaderror pairs for anything that failed
sub _errorlist_for_modreqs {
  # args supposedly already went through _groups_to_reqs and are therefore sanitized
  # safe to eval at will
  my ($self, $reqs) = @_;

  my $ret;

  for my $m ( keys %$reqs ) {
    my $v = $reqs->{$m};

    if (! exists $req_unavailability_cache{$m}{$v} ) {
      local $@;
      eval( "require $m;" . ( $v ? "$m->VERSION(q($v))" : '' ) );
      $req_unavailability_cache{$m}{$v} = $@;
    }

    $ret->{$m} = $req_unavailability_cache{$m}{$v}
      if $req_unavailability_cache{$m}{$v};
  }

  $ret;
}


# This is to be called by the author only (automatically in Makefile.PL)
sub _gen_pod {
  my ($class, $distver, $pod_dir) = @_;

  die "No POD root dir supplied" unless $pod_dir;

  $distver ||=
    eval { require DBIx::Class; DBIx::Class->VERSION; }
      ||
    die
"\n\n---------------------------------------------------------------------\n" .
'Unable to load core DBIx::Class module to determine current version, '.
'possibly due to missing dependencies. Author-mode autodocumentation ' .
"halted\n\n" . $@ .
"\n\n---------------------------------------------------------------------\n"
  ;

  # do not ask for a recent version, use 1.x API calls
  # this *may* execute on a smoker with old perl or whatnot
  require File::Path;

  (my $modfn = __PACKAGE__ . '.pm') =~ s|::|/|g;

  (my $podfn = "$pod_dir/$modfn") =~ s/\.pm$/\.pod/;
  (my $dir = $podfn) =~ s|/[^/]+$||;

  File::Path::mkpath([$dir]);

  my $sqltver = $class->req_list_for('deploy')->{'SQL::Translator'}
    or die "Hrmm? No sqlt dep?";


  my @chunks;

#@@
#@@ HEADER
#@@
  push @chunks, <<"EOC";
#########################################################################
#####################  A U T O G E N E R A T E D ########################
#########################################################################
#
# The contents of this POD file are auto-generated.  Any changes you make
# will be lost. If you need to change the generated text edit _gen_pod()
# at the end of $modfn
#

=head1 NAME

$class - Optional module dependency specifications (for module authors)
EOC


#@@
#@@ SYNOPSIS HEADING
#@@
  push @chunks, <<"EOC";
=head1 SYNOPSIS

Somewhere in your build-file (e.g. L<ExtUtils::MakeMaker>'s F<Makefile.PL>):

  ...

  \$EUMM_ARGS{CONFIGURE_REQUIRES} = {
    \%{ \$EUMM_ARGS{CONFIGURE_REQUIRES} || {} },
    'DBIx::Class' => '$distver',
  };

  ...

  my %DBIC_DEPLOY_DEPS = %{ eval {
    require $class;
    $class->req_list_for('deploy');
  } || {} };

  \$EUMM_ARGS{PREREQ_PM} = {
    \%DBIC_DEPLOY_DEPS,
    \%{ \$EUMM_ARGS{PREREQ_PM} || {} },
  };

  ...

  ExtUtils::MakeMaker::WriteMakefile(\%EUMM_ARGS);

B<Note>: The C<eval> protection within the example is due to support for
requirements during L<the C<configure> build phase|CPAN::Meta::Spec/Phases>
not being available on a sufficient portion of production installations of
Perl. Robust support for such dependency requirements is available in the
L<CPAN> installer only since version C<1.94_56> first made available for
production with perl version C<5.12>. It is the belief of the current
maintainer that support for requirements during the C<configure> build phase
will not be sufficiently ubiquitous until the B<year 2020> at the earliest,
hence the extra care demonstrated above. It should also be noted that some
3rd party installers (e.g. L<cpanminus|App::cpanminus>) do the right thing
with configure requirements independent from the versions of perl and CPAN
available.
EOC


#@@
#@@ DESCRIPTION HEADING
#@@
  push @chunks, <<'EOC';
=head1 DESCRIPTION

Some of the less-frequently used features of L<DBIx::Class> have external
module dependencies on their own. In order not to burden the average user
with modules they will never use, these optional dependencies are not included
in the base Makefile.PL. Instead an exception with a descriptive message is
thrown when a specific feature can't find one or several modules required for
its operation. This module is the central holding place for the current list
of such dependencies, for DBIx::Class core authors, and DBIx::Class extension
authors alike.

Dependencies are organized in L<groups|/CURRENT REQUIREMENT GROUPS> where each
group can list one or more required modules, with an optional minimum version
(or 0 for any version). In addition groups prefixed with C<test_> can specify
a set of environment variables, some (or all) of which are marked as required
for the group to be considered by L</req_list_for>

Each group name (or a combination thereof) can be used in the
L<public methods|/METHODS> as described below.
EOC


#@@
#@@ REQUIREMENT GROUPLIST HEADING
#@@
  push @chunks, '=head1 CURRENT REQUIREMENT GROUPS';

  for my $group (sort keys %$dbic_reqs) {
    my $p = $dbic_reqs->{$group}{pod}
      or next;

    my $modlist = $class->modreq_list_for($group);

    next unless keys %$modlist;

    push @chunks, (
      "=head2 $p->{title}",
      "$p->{desc}",
      '=over',
      ( map { "=item * $_" . ($modlist->{$_} ? " >= $modlist->{$_}" : '') } (sort keys %$modlist) ),
      '=back',
      "Requirement group: B<$group>",
    );
  }


#@@
#@@ API DOCUMENTATION HEADING
#@@
  push @chunks, <<'EOC';

=head1 IMPORT-LIKE ACTIONS

Even though this module is not an L<Exporter>, it recognizes several C<actions>
supplied to its C<import> method.

=head2 -skip_all_without

=over

=item Arguments: @group_names

=back

A convenience wrapper for use during testing:
EOC

  push @chunks, " use $class -skip_all_without => qw(admin test_rdbms_mysql);";

  push @chunks, 'Roughly equivalent to the following code:';

  push @chunks, sprintf <<'EOS', ($class) x 2;

 BEGIN {
   require %s;
   if ( my $missing = %s->req_missing_for(\@group_names_) ) {
     print "1..0 # SKIP requirements not satisfied: $missing\n";
     exit 0;
   }
 }
EOS

  push @chunks, <<'EOC';

It also takes into account the C<RELEASE_TESTING> environment variable and
behaves like L</-die_without> for any requirement groups marked as
C<release_testing_mandatory>.

=head2 -die_without

=over

=item Arguments: @group_names

=back

A convenience wrapper around L</die_unless_req_ok_for>:
EOC

  push @chunks, " use $class -die_without => qw(deploy admin);";

  push @chunks, <<'EOC';

=head2 -list_missing

=over

=item Arguments: @group_names

=back

A convenience wrapper around L</modreq_missing_for>:

 perl -Ilib -MDBIx::Class::Optional::Dependencies=-list_missing,deploy,admin | cpanm

=head1 METHODS

=head2 req_group_list

=over

=item Arguments: none

=item Return Value: \%list_of_requirement_groups

=back

This method should be used by DBIx::Class packagers, to get a hashref of all
dependencies B<keyed> by dependency group. Each key (group name), or a combination
thereof (as an arrayref) can be supplied to the methods below.
The B<values> of the returned hash are currently a set of options B<without a
well defined structure>. If you have use for any of the contents - contact the
maintainers, instead of treating this as public (left alone stable) API.

=head2 req_list_for

=over

=item Arguments: $group_name | \@group_names

=item Return Value: \%set_of_module_version_pairs

=back

This method should be used by DBIx::Class extension authors, to determine the
version of modules a specific set of features requires for this version of
DBIx::Class (regardless of their availability on the system).
See the L</SYNOPSIS> for a real-world example.

When handling C<test_*> groups this method behaves B<differently> from
L</modreq_list_for> below (and is the only such inconsistency among the
C<req_*> methods). If a particular group declares as requirements some
C<environment variables> and these requirements are not satisfied (the envvars
are unset) - then the C<module requirements> of this group are not included in
the returned list.

=head2 modreq_list_for

=over

=item Arguments: $group_name | \@group_names

=item Return Value: \%set_of_module_version_pairs

=back

Same as L</req_list_for> but does not take into consideration any
C<environment variable requirements> - returns just the list of required
modules.

=head2 req_ok_for

=over

=item Arguments: $group_name | \@group_names

=item Return Value: 1|0

=back

Returns true or false depending on whether all modules/envvars required by
the group(s) are loadable/set on the system.

=head2 req_missing_for

=over

=item Arguments: $group_name | \@group_names

=item Return Value: $error_message_string

=back

Returns a single-line string suitable for inclusion in larger error messages.
This method would normally be used by DBIx::Class core features, to indicate to
the user that they need to install specific modules and/or set specific
environment variables before being able to use a specific feature set.

For example if some of the requirements for C<deploy> are not available,
the returned string could look like:
EOC

  push @chunks, qq{ "SQL::Translator~>=$sqltver" (see $class documentation for details)};

  push @chunks, <<'EOC';
The author is expected to prepend the necessary text to this message before
returning the actual error seen by the user. See also L</modreq_missing_for>

=head2 modreq_missing_for

=over

=item Arguments: $group_name | \@group_names

=item Return Value: $error_message_string

=back

Same as L</req_missing_for> except that the error string is guaranteed to be
either empty, or contain a set of module requirement specifications suitable
for piping to e.g. L<cpanminus|App::cpanminus>. The method explicitly does not
attempt to validate the state of required environment variables (if any).

For instance if some of the requirements for C<deploy> are not available,
the returned string could look like:
EOC

  push @chunks, qq{ "SQL::Translator~>=$sqltver"};

  push @chunks, <<'EOC';

See also L</-list_missing>.

=head2 die_unless_req_ok_for

=over

=item Arguments: $group_name | \@group_names

=back

Checks if L</req_ok_for> passes for the supplied group(s), and
in case of failure throws an exception including the information
from L</req_missing_for>. See also L</-die_without>.

=head2 modreq_errorlist_for

=over

=item Arguments: $group_name | \@group_names

=item Return Value: \%set_of_loaderrors_per_module

=back

Returns a hashref containing the actual errors that occurred while attempting
to load each module in the requirement group(s).

=head2 req_errorlist_for

Deprecated method name, equivalent (via proxy) to L</modreq_errorlist_for>.

EOC

#@@
#@@ FOOTER
#@@
  push @chunks, <<'EOC';
=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.
EOC

  eval {
    open (my $fh, '>', $podfn) or die;
    print $fh join ("\n\n", @chunks) or die;
    print $fh "\n" or die;
    close ($fh) or die;
  } or croak( "Unable to write $podfn: " . ( $! || $@ || 'unknown error') );
}

1;
