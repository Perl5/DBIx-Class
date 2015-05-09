package DBIx::Class::Optional::Dependencies;

### This may look crazy, but it in fact tangibly ( by 50(!)% ) shortens
#   the skip-test time when everything requested is unavailable
BEGIN {
  if ( $ENV{RELEASE_TESTING} ) {
    require warnings and warnings->import;
    require strict and strict->import;
  }
}

sub croak {
  require Carp;
  Carp::croak(@_);
};
###

# NO EXTERNAL NON-5.8.1 CORE DEPENDENCIES EVER (e.g. C::A::G)
# This module is to be loaded by Makefile.PM on a pristine system

# POD is generated automatically by calling _gen_pod from the
# Makefile.PL in $AUTHOR mode

# *DELIBERATELY* not making a group for these - they must disappear
# forever as optdeps in the first place
my $moose_basic = {
  'Moose'                         => '0.98',
  'MooseX::Types'                 => '0.21',
  'MooseX::Types::LoadableClass'  => '0.011',
};

my $dbic_reqs = {

  # NOTE: the rationale for 2 JSON::Any versions is that
  # we need the newer only to work around JSON::XS, which
  # itself is an optional dep
  _json_any => {
    req => {
      'JSON::Any' => '1.23',
    },
  },

  _json_xs_compatible_json_any => {
    req => {
      'JSON::Any' => '1.31',
    },
  },

  # a common placeholder for engines with IC::DT support based off DT::F::S
  _ic_dt_strptime_based => {
    augment => {
      ic_dt => {
        req => {
          'DateTime::Format::Strptime' => '1.2',
        },
      },
    }
  },

  _rdbms_generic_odbc => {
    req => {
      'DBD::ODBC' => 0,
    }
  },

  _rdbms_generic_ado => {
    req => {
      'DBD::ADO' => 0,
    }
  },

  # must list any dep used by adhoc testing
  # this prevents the "skips due to forgotten deps" issue
  test_adhoc => {
    req => {
      'Class::DBI::Plugin::DeepAbstractSearch' => '0',
      'Class::DBI' => '3.000005',
      'Date::Simple' => '3.03',
      'YAML' => '0',
      'Class::Unload' => '0.07',
      'Time::Piece' => '0',
      'Time::Piece::MySQL' => '0',
    },
  },

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

  config_file_reader => {
    pod => {
      title => 'Generic config reader',
      desc => 'Modules required for generic config file parsing, currently Config::Any (rarely used at runtime)',
    },
    req => {
      'Config::Any' => '0.20',
    },
  },

  admin => {
    include => [qw( _json_any config_file_reader )],
    req => {
      %$moose_basic,
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

  ic_dt => {
    req => {
      'DateTime' => '0.55',
      'DateTime::TimeZone::OlsonDB' => 0,
    },
    pod => {
      title => 'InflateColumn::DateTime support',
      desc =>
        'Modules required for L<DBIx::Class::InflateColumn::DateTime>. '
      . 'Note that this group does not require much on its own, but '
      . 'instead is augmented by various RDBMS-specific groups. See the '
      . 'documentation of each C<rbms_*> group for details',
    },
  },

  id_shortener => {
    req => {
      'Math::BigInt' => '1.80',
      'Math::Base36' => '0.07',
    },
  },

  cdbicompat => {
    req => {
      'Class::Data::Inheritable' => '0',
      'Class::Trigger' => '0',
      'DBIx::ContextualFetch' => '0',
      'Clone' => '0.32',
    },
    pod => {
      title => 'DBIx::Class::CDBICompat support',
      desc => 'Modules required for L<DBIx::Class::CDBICompat>'
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
    include => '_json_any',
  },

  test_admin_script => {
    include => [qw( admin_script _json_xs_compatible_json_any )],
    req => {
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
    augment => {
      ic_dt => {
        req => {
          'DateTime::Format::SQLite' => '0',
        },
      },
    },
  },

  # centralize the specification, as we have ICDT tests which can
  # test the full behavior of RDBMS-specific ICDT on top of bare SQLite
  _ic_dt_pg_base => {
    augment => {
      ic_dt => {
        req => {
          'DateTime::Format::Pg' => '0.16004',
        },
      },
    },
  },

  ic_dt_pg => {
    include => [qw( ic_dt _ic_dt_pg_base )],
  },

  rdbms_pg => {
    include => '_ic_dt_pg_base',
    req => {
      # when changing this list make sure to adjust xt/optional_deps.t
      'DBD::Pg' => 0,
    },
    pod => {
      title => 'PostgreSQL support',
      desc => 'Modules required to connect to PostgreSQL',
    },
  },

  _rdbms_mssql_common => {
    include => '_ic_dt_strptime_based',
  },

  rdbms_mssql_odbc => {
    include => [qw( _rdbms_generic_odbc _rdbms_mssql_common )],
    pod => {
      title => 'MSSQL support via DBD::ODBC',
      desc => 'Modules required to connect to MSSQL via DBD::ODBC',
    },
  },

  rdbms_mssql_sybase => {
    include => '_rdbms_mssql_common',
    req => {
      'DBD::Sybase' => 0,
    },
    pod => {
      title => 'MSSQL support via DBD::Sybase',
      desc => 'Modules required to connect to MSSQL via DBD::Sybase',
    },
  },

  rdbms_mssql_ado => {
    include => [qw( _rdbms_generic_ado _rdbms_mssql_common )],
    pod => {
      title => 'MSSQL support via DBD::ADO (Windows only)',
      desc => 'Modules required to connect to MSSQL via DBD::ADO. This particular DBD is available on Windows only',
    },
  },

  _rdbms_msaccess_common => {
    include => '_ic_dt_strptime_based',
  },

  rdbms_msaccess_odbc => {
    include => [qw( _rdbms_generic_odbc _rdbms_msaccess_common )],
    pod => {
      title => 'MS Access support via DBD::ODBC',
      desc => 'Modules required to connect to MS Access via DBD::ODBC',
    },
  },

  rdbms_msaccess_ado => {
    include => [qw( _rdbms_generic_ado _rdbms_msaccess_common )],
    pod => {
      title => 'MS Access support via DBD::ADO (Windows only)',
      desc => 'Modules required to connect to MS Access via DBD::ADO. This particular DBD is available on Windows only',
    },
  },

  # centralize the specification, as we have ICDT tests which can
  # test the full behavior of RDBMS-specific ICDT on top of bare SQLite
  _ic_dt_mysql_base => {
    augment => {
      ic_dt => {
        req => {
          'DateTime::Format::MySQL' => '0',
        },
      },
    },
  },

  ic_dt_mysql => {
    include => [qw( ic_dt _ic_dt_mysql_base )],
  },

  rdbms_mysql => {
    include => '_ic_dt_mysql_base',
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
    augment => {
      ic_dt => {
        req => {
          'DateTime::Format::Oracle' => '0',
        },
      },
    },
  },

  rdbms_ase => {
    include => '_ic_dt_strptime_based',
    req => {
      'DBD::Sybase' => 0,
    },
    pod => {
      title => 'Sybase ASE support',
      desc => 'Modules required to connect to Sybase ASE',
    },
  },

  _rdbms_db2_common => {
    augment => {
      ic_dt => {
        req => {
          'DateTime::Format::DB2' => '0',
        },
      },
    },
  },

  rdbms_db2 => {
    include => '_rdbms_db2_common',
    req => {
      'DBD::DB2' => 0,
    },
    pod => {
      title => 'DB2 support',
      desc => 'Modules required to connect to DB2',
    },
  },

  rdbms_db2_400 => {
    include => [qw( _rdbms_generic_odbc _rdbms_db2_common )],
    pod => {
      title => 'DB2 on AS/400 support',
      desc => 'Modules required to connect to DB2 on AS/400',
    },
  },

  rdbms_informix => {
    include => '_ic_dt_strptime_based',
    req => {
      'DBD::Informix' => 0,
    },
    pod => {
      title => 'Informix support',
      desc => 'Modules required to connect to Informix',
    },
  },

  _rdbms_sqlanywhere_common => {
    include => '_ic_dt_strptime_based',
  },

  rdbms_sqlanywhere => {
    include => '_rdbms_sqlanywhere_common',
    req => {
      'DBD::SQLAnywhere' => 0,
    },
    pod => {
      title => 'SQLAnywhere support',
      desc => 'Modules required to connect to SQLAnywhere',
    },
  },

  rdbms_sqlanywhere_odbc => {
    include => [qw( _rdbms_generic_odbc _rdbms_sqlanywhere_common )],
    pod => {
      title => 'SQLAnywhere support via DBD::ODBC',
      desc => 'Modules required to connect to SQLAnywhere via DBD::ODBC',
    },
  },

  _rdbms_firebird_common => {
    include => '_ic_dt_strptime_based',
  },

  rdbms_firebird => {
    include => '_rdbms_firebird_common',
    req => {
      'DBD::Firebird' => 0,
    },
    pod => {
      title => 'Firebird support',
      desc => 'Modules required to connect to Firebird',
    },
  },

  rdbms_firebird_interbase => {
    include => '_rdbms_firebird_common',
    req => {
      'DBD::InterBase' => 0,
    },
    pod => {
      title => 'Firebird support via DBD::InterBase',
      desc => 'Modules required to connect to Firebird via DBD::InterBase',
    },
  },

  rdbms_firebird_odbc => {
    include => [qw( _rdbms_generic_odbc _rdbms_firebird_common )],
    pod => {
      title => 'Firebird support via DBD::ODBC',
      desc => 'Modules required to connect to Firebird via DBD::ODBC',
    },
  },

  test_rdbms_sqlite => {
    include => 'rdbms_sqlite',
    req => {
      ###
      ### IMPORTANT - do not raise this dependency
      ### even though many bugfixes are present in newer versions, the general DBIC
      ### rule is to bend over backwards for available DBDs (given upgrading them is
      ### often *not* easy or even possible)
      ###
      'DBD::SQLite' => '1.29',
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
    include => 'rdbms_msaccess_odbc',
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
    include => 'rdbms_msaccess_ado',
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
    # we need to run the dbicadmin so we can self-generate its POD
    # also we do not want surprises in case JSON::XS is in the path
    # so make sure we get an always-working JSON::Any
    include => [qw(
      admin_script
      _json_xs_compatible_json_any
      id_shortener
      deploy
      test_pod
      test_podcoverage
      test_whitespace
      test_strictures
    )],
    req => {
      'ExtUtils::MakeMaker' => '6.64',
      'Module::Install'     => '1.06',
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
  shift->_groups_to_reqs(shift)->{effective_modreqs};
}

sub modreq_list_for {
  shift->_groups_to_reqs(shift)->{modreqs};
}

sub req_group_list {
  +{ map
    { $_ => $_[0]->_groups_to_reqs($_) }
    grep { $_ !~ /^_/ } keys %$dbic_reqs
  }
}

sub req_errorlist_for { shift->modreq_errorlist_for(shift) }  # deprecated
sub modreq_errorlist_for {
  my ($self, $groups) = @_;
  $self->_errorlist_for_modreqs( $self->_groups_to_reqs($groups)->{modreqs} );
}

sub req_ok_for {
  shift->req_missing_for(shift) ? 0 : 1;
}

sub req_missing_for {
  my ($self, $groups) = @_;

  my $reqs = $self->_groups_to_reqs($groups);

  my $mods_missing = $reqs->{missing_envvars}
    ? $self->_list_physically_missing_modules( $reqs->{modreqs} )
    : $self->modreq_missing_for($groups)
  ;

  return '' if
    ! $mods_missing
      and
    ! $reqs->{missing_envvars}
  ;

  my @res = $mods_missing || ();

  push @res, 'the following group(s) of environment variables: ' . join ' and ', sort map
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
  my ($self, $groups) = @_;

  my $reqs = $self->_groups_to_reqs($groups);
  my $modreq_errors = $self->_errorlist_for_modreqs($reqs->{modreqs})
    or return '';

  join ' ', map
    { $reqs->{modreqs}{$_} ? "$_~$reqs->{modreqs}{$_}" : $_ }
    sort { lc($a) cmp lc($b) } keys %$modreq_errors
  ;
}

my $tb;
sub skip_without {
  my ($self, $groups) = @_;

  $tb ||= do { local $@; eval { Test::Builder->new } }
    or croak "Calling skip_without() before loading Test::Builder makes no sense";

  if ( my $err = $self->req_missing_for($groups) ) {
    my ($fn, $ln) = (caller(0))[1,2];
    $tb->skip("block in $fn around line $ln requires $err");
    local $^W = 0;
    last SKIP;
  }

  1;
}

sub die_unless_req_ok_for {
  if (my $err = shift->req_missing_for(shift) ) {
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

my $groupname_re = qr/ [a-z_] [0-9_a-z]* /x;
my $modname_re = qr/ [A-Z_a-z] [0-9A-Z_a-z]* (?:::[0-9A-Z_a-z]+)* /x;
my $modver_re = qr/ [0-9]+ (?: \. [0-9]+ )? /x;

# Expand includes from a random group in a specific order:
# nonvariable groups first, then their includes, then the variable groups,
# then their includes.
# This allows reliably marking the rest of the mod reqs as variable (this is
# also why variable includes are currently not allowed)
sub __expand_includes {
  my ($groups, $seen) = @_;

  # !! DIFFERENT !! behavior and return depending on invocation mode
  # (easier to recurse this way)
  my $is_toplevel = $seen
    ? 0
    : !! ($seen = {})
  ;

  my ($res_per_type, $missing_envvars);

  # breadth-first evaluation, with non-variable includes on top
  for my $g (@$groups) {

    croak "Invalid requirement group name '$g': only ascii alphanumerics and _ are allowed"
      if $g !~ qr/ \A $groupname_re \z/x;

    my $r = $dbic_reqs->{$g}
      or croak "Requirement group '$g' is not defined";

    # always do this check *before* the $seen check
    croak "Group '$g' with variable effective_modreqs can not be specified as an 'include'"
      if ( $r->{env} and ! $is_toplevel );

    next if $seen->{$g}++;

    my $req_type = 'static';

    if ( my @e = @{$r->{env}||[]} ) {

      croak "Unexpected 'env' attribute under group '$g' (only allowed in test_* groups)"
        unless $g =~ /^test_/;

      croak "Unexpected *odd* list in 'env' under group '$g'"
        if @e % 2;

      # deconstruct the whole thing
      my (@group_envnames_list, $some_envs_required, $some_required_missing);
      while (@e) {
        push @group_envnames_list, my $envname = shift @e;

        # env required or not
        next unless shift @e;

        $some_envs_required ||= 1;

        $some_required_missing ||= (
          ! defined $ENV{$envname}
            or
          ! length $ENV{$envname}
        );
      }

      croak "None of the envvars in group '$g' declared as required, making the requirement moot"
        unless $some_envs_required;

      if ($some_required_missing) {
        push @{$missing_envvars->{$g}}, \@group_envnames_list;
        $req_type = 'variable';
      }
    }

    push @{$res_per_type->{"base_${req_type}"}}, $g;

    if (my $i = $dbic_reqs->{$g}{include}) {
      $i = [ $i ] unless ref $i eq 'ARRAY';

      croak "Malformed 'include' for group '$g': must be another existing group name or arrayref of existing group names"
        unless @$i;

      push @{$res_per_type->{"incs_${req_type}"}}, @$i;
    }
  }

  my @ret = map {
    @{ $res_per_type->{"base_${_}"} || [] },
    ( $res_per_type->{"incs_${_}"} ? __expand_includes( $res_per_type->{"incs_${_}"}, $seen ) : () ),
  } qw(static variable);

  return ! $is_toplevel ? @ret : do {
    my $rv = {};
    $rv->{$_} = {
      idx => 1 + keys %$rv,
      missing_envvars => $missing_envvars->{$_},
    } for @ret;
    $rv->{$_}{user_requested} = 1 for @$groups;
    $rv;
  };
}

### Private OO API
our %req_unavailability_cache;

# this method is just a lister and envvar/metadata checker - it does not try to load anything
sub _groups_to_reqs {
  my ($self, $want) = @_;

  $want = [ $want || () ]
    unless ref $want eq 'ARRAY';

  croak "@{[ (caller(1))[3] ]}() expects a requirement group name or arrayref of group names"
    unless @$want;

  my $ret = {
    modreqs => {},
    modreqs_fully_documented => 1,
  };

  my $groups;
  for my $piece (@$want) {
    if ($piece =~ qr/ \A $groupname_re \z /x) {
      push @$groups, $piece;
    }
    elsif ( my ($mod, $ver) = $piece =~ qr/ \A ($modname_re) \>\= ($modver_re) \z /x ) {
      croak "Ad hoc module specification lists '$mod' twice"
        if exists $ret->{modreqs}{$mod};

      croak "Ad hoc module specification '${mod} >= $ver' (or greater) not listed in the test_adhoc optdep group" if (
        ! defined $dbic_reqs->{test_adhoc}{req}{$mod}
          or
        $dbic_reqs->{test_adhoc}{req}{$mod} < $ver
      );

      $ret->{modreqs}{$mod} = $ver;
      $ret->{modreqs_fully_documented} = 0;
    }
    else {
      croak "Unsupported argument '$piece' supplied to @{[ (caller(1))[3] ]}()"
    }
  }

  my $all_groups = __expand_includes($groups);

  # pre-assemble list of augmentations, perform basic sanity checks
  # Note that below we *DO NOT* respect the source/target reationship, but
  # instead always default to augment the "later" group
  # This is done so that the "stable/variable" boundary keeps working as
  # expected
  my $augmentations;
  for my $requesting_group (keys %$all_groups) {
    if (my $ag = $dbic_reqs->{$requesting_group}{augment}) {
      for my $target_group (keys %$ag) {

        croak "Group '$requesting_group' claims to augment a non-existent group '$target_group'"
          unless $dbic_reqs->{$target_group};

        croak "Augmentation combined with variable effective_modreqs currently unsupported for group '$requesting_group'"
          if $dbic_reqs->{$requesting_group}{env};

        croak "Augmentation of group '$target_group' with variable effective_modreqs unsupported (requested by '$requesting_group')"
          if $dbic_reqs->{$target_group}{env};

        if (my @foreign = grep { $_ ne 'req' } keys %{$ag->{$target_group}} ) {
          croak "Only 'req' augmentations are currently supported (group '$requesting_group' attempts to alter '$foreign[0]' of group '$target_group'";
        }

        $ret->{augments}{$target_group} = 1;

        # no augmentation for stuff that hasn't been selected
        if ( $all_groups->{$target_group} and my $ar = $ag->{$target_group}{req} ) {
          push @{$augmentations->{
            ( $all_groups->{$requesting_group}{idx} < $all_groups->{$target_group}{idx} )
              ? $target_group
              : $requesting_group
          }}, $ar;
        }
      }
    }
  }

  for my $group (sort { $all_groups->{$a}{idx} <=> $all_groups->{$b}{idx} } keys %$all_groups ) {

    my $group_reqs = $dbic_reqs->{$group}{req};

    # sanity-check
    for my $req_bag ($group_reqs, @{ $augmentations->{$group} || [] } ) {
      for (keys %$req_bag) {

        $_ =~ / \A $modname_re \z /x
          or croak "Requirement '$_' in group '$group' is not a valid module name";

        # !!!DO NOT CHANGE!!!
        # remember - version.pm may not be available on the system
        croak "Requirement '$_' in group '$group' specifies an invalid version '$req_bag->{$_}' (only plain non-underscored floating point decimals are supported)"
          if ( ($req_bag->{$_}||0) !~ qr/ \A $modver_re \z /x );
      }
    }

    if (my $e = $all_groups->{$group}{missing_envvars}) {
      push @{$ret->{missing_envvars}}, @$e;
    }

    # assemble into the final ret
    for my $type (
      'modreqs',
      ( $ret->{missing_envvars} ? () : 'effective_modreqs' ),
    ) {
      for my $req_bag ($group_reqs, @{ $augmentations->{$group} || [] } ) {
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

    $ret->{modreqs_fully_documented} &&= !!$dbic_reqs->{$group}{pod}
      if $all_groups->{$group}{user_requested};

    $ret->{release_testing_mandatory} ||= !!$dbic_reqs->{$group}{release_testing_mandatory};
  }

  return $ret;
}


# this method tries to find/load specified modreqs and returns a hashref of
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

# Unlike the above DO NOT try to load anything
# This is executed when some needed envvars are not available
# which in turn means a module load will never be reached anyway
# This is important because some modules (especially DBDs) can be
# *really* fickle when a require() is attempted, with pretty confusing
# side-effects (especially on windows)
sub _list_physically_missing_modules {
  my ($self, $modreqs) = @_;

  # in case there is a coderef in @INC there is nothing we can definitively prove
  # so short circuit directly
  return '' if grep { length ref $_ } @INC;

  my @definitely_missing;
  for my $mod (keys %$modreqs) {
    (my $fn = $mod . '.pm') =~ s|::|/|g;

    push @definitely_missing, $mod unless grep
      # this should work on any combination of slashes
      { $_ and -d $_ and -f "$_/$fn" and -r "$_/$fn" }
      @INC
    ;
  }

  join ' ', map
    { $modreqs->{$_} ? "$_~$modreqs->{$_}" : $_ }
    sort { lc($a) cmp lc($b) } @definitely_missing
  ;
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

  my %DBIC_DEPLOY_AND_ORACLE_DEPS = %{ eval {
    require $class;
    $class->req_list_for([qw( deploy rdbms_oracle ic_dt )]);
  } || {} };

  \$EUMM_ARGS{PREREQ_PM} = {
    \%DBIC_DEPLOY_AND_ORACLE_DEPS,
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

  my $standalone_info;

  for my $group (sort keys %$dbic_reqs) {

    my $info = $standalone_info->{$group} ||= $class->_groups_to_reqs($group);

    next unless (
      $info->{modreqs_fully_documented}
        and
      ( $info->{augments} or $info->{modreqs} )
    );

    my $p = $dbic_reqs->{$group}{pod};

    push @chunks, (
      "=head2 $p->{title}",
      "=head3 $group",
      $p->{desc},
      '=over',
    );

    if ( keys %{ $info->{modreqs}||{} } ) {
      push @chunks, map
        { "=item * $_" . ($info->{modreqs}{$_} ? " >= $info->{modreqs}{$_}" : '') }
        ( sort keys %{ $info->{modreqs} } )
      ;
    }
    else {
      push @chunks, '=item * No standalone requirements',
    }

    push @chunks, '=back';

    for my $ag ( sort keys %{ $info->{augments} || {} } ) {
      my $ag_info = $standalone_info->{$ag} ||= $class->_groups_to_reqs($ag);

      my $newreqs = $class->modreq_list_for([ $group, $ag ]);
      for (keys %$newreqs) {
        delete $newreqs->{$_} if (
          ( defined $info->{modreqs}{$_}    and $info->{modreqs}{$_}    == $newreqs->{$_} )
            or
          ( defined $ag_info->{modreqs}{$_} and $ag_info->{modreqs}{$_} == $newreqs->{$_} )
        );
      }

      if (keys %$newreqs) {
        push @chunks, (
          "Combined with L</$ag> additionally requires:",
          '=over',
          ( map
            { "=item * $_" . ($newreqs->{$_} ? " >= $newreqs->{$_}" : '') }
            ( sort keys %$newreqs )
          ),
          '=back',
        );
      }
    }
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

  push @chunks, qq{ "SQL::Translator~$sqltver" (see $class documentation for details)};

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

  push @chunks, qq{ "SQL::Translator~$sqltver"};

  push @chunks, <<'EOC';

See also L</-list_missing>.

=head2 skip_without

=over

=item Arguments: $group_name | \@group_names

=back

A convenience wrapper around L<skip|Test::More/SKIP>. It does not take neither
a reason (it is generated by L</req_missing_for>) nor an amount of skipped tests
(it is always C<1>, thus mandating unconditional use of
L<done_testing|Test::More/done_testing>). Most useful in combination with ad hoc
requirement specifications:
EOC

  push @chunks, <<EOC;
  SKIP: {
    $class->skip_without([ deploy YAML>=0.90 ]);

    ...
  }
EOC

  push @chunks, <<'EOC';

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
