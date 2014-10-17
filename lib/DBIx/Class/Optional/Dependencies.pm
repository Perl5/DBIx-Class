package DBIx::Class::Optional::Dependencies;

use warnings;
use strict;

use Carp;

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

my $replicated = {
  %$moose_basic,
};

my $admin_basic = {
  %$moose_basic,
  %$min_json_any,
  'MooseX::Types::Path::Class'    => '0.05',
  'MooseX::Types::JSON'           => '0.02',
};

my $admin_script = {
  %$moose_basic,
  %$admin_basic,
  'Getopt::Long::Descriptive' => '0.081',
  'Text::CSV'                 => '1.16',
};

my $datetime_basic = {
  'DateTime'                      => '0.55',
  'DateTime::Format::Strptime'    => '1.2',
};

my $id_shortener = {
  'Math::BigInt'                  => '1.80',
  'Math::Base36'                  => '0.07',
};

my $rdbms_sqlite = {
  'DBD::SQLite'                   => '0',
};
my $rdbms_pg = {
  'DBD::Pg'                       => '0',
};
my $rdbms_mssql_odbc = {
  'DBD::ODBC'                     => '0',
};
my $rdbms_mssql_sybase = {
  'DBD::Sybase'                   => '0',
};
my $rdbms_mssql_ado = {
  'DBD::ADO'                      => '0',
};
my $rdbms_msaccess_odbc = {
  'DBD::ODBC'                     => '0',
};
my $rdbms_msaccess_ado = {
  'DBD::ADO'                      => '0',
};
my $rdbms_mysql = {
  'DBD::mysql'                    => '0',
};
my $rdbms_oracle = {
  'DBD::Oracle'                   => '0',
  %$id_shortener,
};
my $rdbms_ase = {
  'DBD::Sybase'                   => '0',
};
my $rdbms_db2 = {
  'DBD::DB2'                      => '0',
};
my $rdbms_db2_400 = {
  'DBD::ODBC'                     => '0',
};
my $rdbms_informix = {
  'DBD::Informix'                 => '0',
};
my $rdbms_sqlanywhere = {
  'DBD::SQLAnywhere'              => '0',
};
my $rdbms_sqlanywhere_odbc = {
  'DBD::ODBC'                     => '0',
};
my $rdbms_firebird = {
  'DBD::Firebird'                 => '0',
};
my $rdbms_firebird_interbase = {
  'DBD::InterBase'                => '0',
};
my $rdbms_firebird_odbc = {
  'DBD::ODBC'                     => '0',
};

my $dbic_reqs = {
  replicated => {
    req => $replicated,
    pod => {
      title => 'Storage::Replicated',
      desc => 'Modules required for L<DBIx::Class::Storage::DBI::Replicated>',
    },
  },

  test_replicated => {
    req => {
      %$replicated,
      'Test::Moose'               => '0',
    },
  },


  admin => {
    req => {
      %$admin_basic,
    },
    pod => {
      title => 'DBIx::Class::Admin',
      desc => 'Modules required for the DBIx::Class administrative library',
    },
  },

  admin_script => {
    req => {
      %$admin_script,
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
    req => $id_shortener,
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
  },

  test_podcoverage => {
    req => {
      'Test::Pod::Coverage'       => '1.08',
      'Pod::Coverage'             => '0.20',
    },
  },

  test_whitespace => {
    req => {
      'Test::EOL'                 => '1.0',
      'Test::NoTabs'              => '0.9',
    },
  },

  test_strictures => {
    req => {
      'Test::Strict'              => '0.20',
    },
  },

  test_prettydebug => {
    req => $min_json_any,
  },

  test_admin_script => {
    req => {
      %$admin_script,
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
    req => $datetime_basic,
  },

  test_dt_sqlite => {
    req => {
      %$datetime_basic,
      # t/36datetime.t
      # t/60core.t
      'DateTime::Format::SQLite'  => '0',
    },
  },

  test_dt_mysql => {
    req => {
      %$datetime_basic,
      # t/inflate/datetime_mysql.t
      # (doesn't need Mysql itself)
      'DateTime::Format::MySQL'   => '0',
    },
  },

  test_dt_pg => {
    req => {
      %$datetime_basic,
      # t/inflate/datetime_pg.t
      # (doesn't need PG itself)
      'DateTime::Format::Pg'      => '0.16004',
    },
  },

  test_cdbicompat => {
    req => {
      'Class::DBI::Plugin::DeepAbstractSearch' => '0',
      %$datetime_basic,
      'Time::Piece::MySQL'        => '0',
      'Date::Simple'              => '3.03',
    },
  },

  # this is just for completeness as SQLite
  # is a core dep of DBIC for testing
  rdbms_sqlite => {
    req => {
      %$rdbms_sqlite,
    },
    pod => {
      title => 'SQLite support',
      desc => 'Modules required to connect to SQLite',
    },
  },

  rdbms_pg => {
    req => {
      # when changing this list make sure to adjust xt/optional_deps.t
      %$rdbms_pg,
    },
    pod => {
      title => 'PostgreSQL support',
      desc => 'Modules required to connect to PostgreSQL',
    },
  },

  rdbms_mssql_odbc => {
    req => {
      %$rdbms_mssql_odbc,
    },
    pod => {
      title => 'MSSQL support via DBD::ODBC',
      desc => 'Modules required to connect to MSSQL via DBD::ODBC',
    },
  },

  rdbms_mssql_sybase => {
    req => {
      %$rdbms_mssql_sybase,
    },
    pod => {
      title => 'MSSQL support via DBD::Sybase',
      desc => 'Modules required to connect to MSSQL via DBD::Sybase',
    },
  },

  rdbms_mssql_ado => {
    req => {
      %$rdbms_mssql_ado,
    },
    pod => {
      title => 'MSSQL support via DBD::ADO (Windows only)',
      desc => 'Modules required to connect to MSSQL via DBD::ADO. This particular DBD is available on Windows only',
    },
  },

  rdbms_msaccess_odbc => {
    req => {
      %$rdbms_msaccess_odbc,
    },
    pod => {
      title => 'MS Access support via DBD::ODBC',
      desc => 'Modules required to connect to MS Access via DBD::ODBC',
    },
  },

  rdbms_msaccess_ado => {
    req => {
      %$rdbms_msaccess_ado,
    },
    pod => {
      title => 'MS Access support via DBD::ADO (Windows only)',
      desc => 'Modules required to connect to MS Access via DBD::ADO. This particular DBD is available on Windows only',
    },
  },

  rdbms_mysql => {
    req => {
      %$rdbms_mysql,
    },
    pod => {
      title => 'MySQL support',
      desc => 'Modules required to connect to MySQL',
    },
  },

  rdbms_oracle => {
    req => {
      %$rdbms_oracle,
    },
    pod => {
      title => 'Oracle support',
      desc => 'Modules required to connect to Oracle',
    },
  },

  rdbms_ase => {
    req => {
      %$rdbms_ase,
    },
    pod => {
      title => 'Sybase ASE support',
      desc => 'Modules required to connect to Sybase ASE',
    },
  },

  rdbms_db2 => {
    req => {
      %$rdbms_db2,
    },
    pod => {
      title => 'DB2 support',
      desc => 'Modules required to connect to DB2',
    },
  },

  rdbms_db2_400 => {
    req => {
      %$rdbms_db2_400,
    },
    pod => {
      title => 'DB2 on AS/400 support',
      desc => 'Modules required to connect to DB2 on AS/400',
    },
  },

  rdbms_informix => {
    req => {
      %$rdbms_informix,
    },
    pod => {
      title => 'Informix support',
      desc => 'Modules required to connect to Informix',
    },
  },

  rdbms_sqlanywhere => {
    req => {
      %$rdbms_sqlanywhere,
    },
    pod => {
      title => 'SQLAnywhere support',
      desc => 'Modules required to connect to SQLAnywhere',
    },
  },

  rdbms_sqlanywhere_odbc => {
    req => {
      %$rdbms_sqlanywhere_odbc,
    },
    pod => {
      title => 'SQLAnywhere support via DBD::ODBC',
      desc => 'Modules required to connect to SQLAnywhere via DBD::ODBC',
    },
  },

  rdbms_firebird => {
    req => {
      %$rdbms_firebird,
    },
    pod => {
      title => 'Firebird support',
      desc => 'Modules required to connect to Firebird',
    },
  },

  rdbms_firebird_interbase => {
    req => {
      %$rdbms_firebird_interbase,
    },
    pod => {
      title => 'Firebird support via DBD::InterBase',
      desc => 'Modules required to connect to Firebird via DBD::InterBase',
    },
  },

  rdbms_firebird_odbc => {
    req => {
      %$rdbms_firebird_odbc,
    },
    pod => {
      title => 'Firebird support via DBD::ODBC',
      desc => 'Modules required to connect to Firebird via DBD::ODBC',
    },
  },

  test_rdbms_pg => {
    req => {
      $ENV{DBICTEST_PG_DSN}
        ? (
          # the order does matter because the rdbms support group might require
          # a different version that the test group
          #
          # when changing this list make sure to adjust xt/optional_deps.t
          %$rdbms_pg,
          'DBD::Pg'               => '2.009002',
        ) : ()
    },
  },

  test_rdbms_mssql_odbc => {
    req => {
      $ENV{DBICTEST_MSSQL_ODBC_DSN}
        ? (
          %$rdbms_mssql_odbc,
        ) : ()
    },
  },

  test_rdbms_mssql_ado => {
    req => {
      $ENV{DBICTEST_MSSQL_ADO_DSN}
        ? (
          %$rdbms_mssql_ado,
        ) : ()
    },
  },

  test_rdbms_mssql_sybase => {
    req => {
      $ENV{DBICTEST_MSSQL_DSN}
        ? (
          %$rdbms_mssql_sybase,
        ) : ()
    },
  },

  test_rdbms_msaccess_odbc => {
    req => {
      $ENV{DBICTEST_MSACCESS_ODBC_DSN}
        ? (
          %$rdbms_msaccess_odbc,
          %$datetime_basic,
          'Data::GUID' => '0',
        ) : ()
    },
  },

  test_rdbms_msaccess_ado => {
    req => {
      $ENV{DBICTEST_MSACCESS_ADO_DSN}
        ? (
          %$rdbms_msaccess_ado,
          %$datetime_basic,
          'Data::GUID' => 0,
        ) : ()
    },
  },

  test_rdbms_mysql => {
    req => {
      $ENV{DBICTEST_MYSQL_DSN}
        ? (
          %$rdbms_mysql,
        ) : ()
    },
  },

  test_rdbms_oracle => {
    req => {
      $ENV{DBICTEST_ORA_DSN}
        ? (
          %$rdbms_oracle,
          'DateTime::Format::Oracle' => '0',
          'DBD::Oracle'              => '1.24',
        ) : ()
    },
  },

  test_rdbms_ase => {
    req => {
      $ENV{DBICTEST_SYBASE_DSN}
        ? (
          %$rdbms_ase,
        ) : ()
    },
  },

  test_rdbms_db2 => {
    req => {
      $ENV{DBICTEST_DB2_DSN}
        ? (
          %$rdbms_db2,
        ) : ()
    },
  },

  test_rdbms_db2_400 => {
    req => {
      $ENV{DBICTEST_DB2_400_DSN}
        ? (
          %$rdbms_db2_400,
        ) : ()
    },
  },

  test_rdbms_informix => {
    req => {
      $ENV{DBICTEST_INFORMIX_DSN}
        ? (
          %$rdbms_informix,
        ) : ()
    },
  },

  test_rdbms_sqlanywhere => {
    req => {
      $ENV{DBICTEST_SQLANYWHERE_DSN}
        ? (
          %$rdbms_sqlanywhere,
        ) : ()
    },
  },

  test_rdbms_sqlanywhere_odbc => {
    req => {
      $ENV{DBICTEST_SQLANYWHERE_ODBC_DSN}
        ? (
          %$rdbms_sqlanywhere_odbc,
        ) : ()
    },
  },

  test_rdbms_firebird => {
    req => {
      $ENV{DBICTEST_FIREBIRD_DSN}
        ? (
          %$rdbms_firebird,
        ) : ()
    },
  },

  test_rdbms_firebird_interbase => {
    req => {
      $ENV{DBICTEST_FIREBIRD_INTERBASE_DSN}
        ? (
          %$rdbms_firebird_interbase,
        ) : ()
    },
  },

  test_rdbms_firebird_odbc => {
    req => {
      $ENV{DBICTEST_FIREBIRD_ODBC_DSN}
        ? (
          %$rdbms_firebird_odbc,
        ) : ()
    },
  },

  test_memcached => {
    req => {
      $ENV{DBICTEST_MEMCACHED}
        ? (
          'Cache::Memcached' => 0,
        ) : ()
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

# OO for (mistakenly considered) ease of extensibility, not due to any need to
# carry state of any sort. This API is currently used outside, so leave as-is.
# FIXME - make sure to not propagate this further if module is extracted as a
# standalone library - keep the stupidity to a DBIC-secific shim!
#
sub req_list_for {
  shift->_groups_to_reqs(@_)->{modreqs};
}

sub req_group_list {
  +{ map
    { $_ => $_[0]->_groups_to_reqs($_) }
    keys %$dbic_reqs
  }
}

sub req_errorlist_for {
  my $self = shift;
  $self->_errorlist_for_modreqs( $self->_groups_to_reqs(@_)->{modreqs} );
}

sub req_ok_for {
  my $self = shift;
  $self->_errorlist_for_modreqs( $self->_groups_to_reqs(@_)->{modreqs} )
    ? 0
    : 1
  ;
}

sub req_missing_for {
  my $self = shift;

  my $reqs = $self->_groups_to_reqs(@_);
  my $modreq_errors = $self->_errorlist_for_modreqs($reqs->{modreqs}) or return '';

  join ' ',
    (map { $reqs->{modreqs}{$_} ? qq("$_~>=$reqs->{modreqs}{$_}") : $_ } sort keys %$modreq_errors),
    ( $reqs->{modreqs_fully_documented} ? "(see @{[ ref $self || $self ]} documentation for details)" : () ),
  ;
}

sub die_unless_req_ok_for {
  if (my $err = shift->req_missing_for(@_) ) {
    die "Required modules missing, unable to continue: $err\n";
  }
}



### Private OO API
our %req_unavailability_cache;

# this method is just a lister/metadata checker - it does not try to load anything
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


  for my $group ( @$groups ) {

    $group =~ /\A [A-Za-z][0-9A-Z_a-z]* \z/x
      or croak "Invalid requirement group name '$group': only ascii alphanumerics and _ are allowed";

    my $group_reqs = ($dbic_reqs->{$group}||{})->{req}
      or croak "Requirement group '$group' is not defined";

    # sanity-check
    for (keys %$group_reqs) {

      $_ =~ /\A [A-Z_a-z][0-9A-Z_a-z]* (?:::[0-9A-Z_a-z]+)* \z /x
        or croak "Requirement '$_' in group '$group' is not a valid module name";

      # !!!DO NOT CHANGE!!!
      # remember - version.pm may not be available on the system
      croak "Requirement '$_' in group '$group' specifies an invalid version '$group_reqs->{$_}' (only plain non-underscored floating point decimals are supported)"
        if ( ($group_reqs->{$_}||0) !~ / \A [0-9]+ (?: \. [0-9]+ )? \z /x );
    }

    # assemble into the final ret
    for (keys %$group_reqs) {

      $ret->{modreqs}{$_} = $group_reqs->{$_}||0 if (

        ! exists $ret->{modreqs}{$_}
          or
        # we sanitized the version to be numeric above - we can just -gt it
        ($group_reqs->{$_}||0) > $ret->{modreqs}{$_}

      );
    }

    $ret->{modreqs_fully_documented} &&= !!$dbic_reqs->{$group}{pod};
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
(or 0 for any version). Each group name (or a combination thereof) can be used
in the L<public methods|/METHODS> as described below.
EOC


#@@
#@@ REQUIREMENT GROUPLIST HEADING
#@@
  push @chunks, '=head1 CURRENT REQUIREMENT GROUPS';

  for my $group (sort keys %$dbic_reqs) {
    my $p = $dbic_reqs->{$group}{pod}
      or next;

    my $modlist = $dbic_reqs->{$group}{req}
      or next;

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
DBIx::Class. See the L</SYNOPSIS> for a real-world example.

=head2 req_ok_for

=over

=item Arguments: $group_name | \@group_names

=item Return Value: 1|0

=back

Returns true or false depending on whether all modules required by
the group(s) are present on the system and loadable.

=head2 req_missing_for

=over

=item Arguments: $group_name | \@group_names

=item Return Value: $error_message_string

=back

Returns a single-line string suitable for inclusion in larger error messages.
This method would normally be used by DBIx::Class core-modules, to indicate to
the user that they need to install specific modules before being able to use a
specific feature set.

For example if some of the requirements for C<deploy> are not available,
the returned string could look like:
EOC

  push @chunks, qq{ "SQL::Translator~>=$sqltver" (see $class documentation for details)};

  push @chunks, <<'EOC';
The author is expected to prepend the necessary text to this message before
returning the actual error seen by the user.

=head2 die_unless_req_ok_for

=over

=item Arguments: $group_name | \@group_names

=back

Checks if L</req_ok_for> passes for the supplied group(s), and
in case of failure throws an exception including the information
from L</req_missing_for>.

=head2 req_errorlist_for

=over

=item Arguments: $group_name | \@group_names

=item Return Value: \%set_of_loaderrors_per_module

=back

Returns a hashref containing the actual errors that occurred while attempting
to load each module in the requirement group(s).
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
