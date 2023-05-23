#!/bin/bash

export SHORT_CIRCUIT_SMOKE

# Stop possibly pre-started RDBMS, move their data back to disk (save RAM)
# sync for some settle time (not available on all platforms)
for d in mysql postgresql ; do
  # maybe not even running
  run_or_err "Stopping $d" "sudo /etc/init.d/$d stop || /bin/true"

  # no longer available on newer build systems
  if [[ -d /var/ramfs/$d ]] ; then
    sudo rm -rf /var/lib/$d
    sudo mv /var/ramfs/$d /var/lib/
    sudo ln -s /var/lib/$d /var/ramfs/$d
  fi
done
/bin/sync

# Sanity check VM before continuing
echo "
=============================================================================

= Startup Meminfo
$(free -m -t)

============================================================================="

# pull requests are always scrutinized after the fact anyway - run a
# a simpler matrix
if [[ "$TRAVIS_PULL_REQUEST" != "false" ]]; then
  if [[ -n "$BREWVER" ]]; then
    # just don't brew anything
    SHORT_CIRCUIT_SMOKE=1
  else
    # running PRs with 1 thread is non-sensical
    VCPU_USE=""
  fi
fi

if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

# Previously we were going off the OpenVZ vcpu count and dividing by 3
# With the new infrastructure, somply go with "something high"
export VCPU_AVAILABLE=10

if [[ -z "$VCPU_USE" ]] ; then
  export VCPU_USE="$VCPU_AVAILABLE"
fi


if [[ "$CLEANTEST" != "true" ]]; then

  if [[ -z "$(tail -n +2 /proc/swaps)" ]] ; then
    run_or_err "Configuring swap (for Oracle)" \
      "sudo bash -c '( fallocate -l 1280M /swap.img || dd if=/dev/zero of=/swap.img bs=256M count=5 ) && chmod 600 /swap.img && mkswap /swap.img && swapon /swap.img'"
  fi


  # never installed, this looks like trusty
  if [[ ! -d /var/lib/mysql ]] ; then
    sudo dpkg --add-architecture i386
    extra_debs+=( postgresql mysql-server )
  fi


  # these APT sources do not mean anything to us anyway
  sudo rm -rf /etc/apt/sources.list.d/*
  sudo rm -rf /var/lib/apt/lists/*
  sudo apt-get clean

  # make sure all versions of apt DTRT
  echo 'Acquire::CompressionTypes::Order:: { "gz"; "xz"; };' | sudo tee -a /etc/apt/apt.conf.d/99CI-repo-compression-workaround

  #
  # FIXME these debconf lines should automate the firebird config but seem not to :(((
  sudo bash -c 'echo -e "firebird2.5-super\tshared/firebird/enabled\tboolean\ttrue" | debconf-set-selections'
  sudo bash -c 'echo -e "firebird2.5-super\tshared/firebird/sysdba_password/new_password\tpassword\t123" | debconf-set-selections'

  run_or_err "Updating APT sources" "sudo apt-get update"
  apt_install ${extra_debs[@]} libmysqlclient-dev memcached firebird2.5-super firebird2.5-dev


  # need to stop them again, in case we installed them above (trusty)
  for d in mysql postgresql ; do
    run_or_err "Stopping $d" "sudo /etc/init.d/$d stop || /bin/true"
  done


  export CACHE_DIR="/tmp/poormanscache"
  mkdir "$CACHE_DIR"

  run_or_err "Getting DB2 from poor man's cache github" '
    wget -qO- https://github.com/poormanscache/poormanscache/archive/DB2_ExC/9.7.5_deb_x86-64.tar.gz \
  | tar -C "$CACHE_DIR" -zx'

  # the actual package is built for lucid, installs seemingly fine
  manual_debs+=( "db2exc_9.7.5-0lucid0_amd64.deb" )

  run_or_err "Getting Oracle from poor man's cache github" '
    wget -qO- https://github.com/poormanscache/poormanscache/archive/OracleXE/10.2.0_deb_mixed.tar.gz \
  | tar -C "$CACHE_DIR" -zx'
  manual_debs+=( "bc-multiarch-travis_1.0_all.deb" "oracle-xe_10.2.0.1-1.1_i386.deb" )


  # reassemble chunked pieces ( working around github's filesize limit )
  for reass in $CACHE_DIR/*/reassemble ; do /bin/bash "$reass" ; done

  run_or_err "Installing RDBMS debs manually: $( echo ${manual_debs[@]/#/$CACHE_DIR/*/*/} )" \
    "sudo dpkg -i $( echo ${manual_debs[@]/#/$CACHE_DIR/*/*/} ) || sudo bash -c 'source maint/travis-ci_scripts/common.bash && apt_install -f'"


  # needs to happen separately and *after* db2exc, as the former shits all over /usr/include (wtf?!)
  # the --reinstall is needed to fixup an already-installed lib on newer ubuntu's
  # for more info look at /opt/ibm/db2/V9.7/instance/db2iutil :: create_links()
  apt_install --reinstall unixodbc-dev


### config memcached
  run_or_err "Starting memcached" "sudo /etc/init.d/memcached start"
  export DBICTEST_MEMCACHED=127.0.0.1:11211

### config mysql
  run_or_err "Installing minimizing MySQL config" "\
     sudo bash -c 'rm /var/lib/mysql/ib*' \
  && sudo cp maint/travis-ci_scripts/configs/minimal_mysql_travis.cnf /etc/mysql/conf.d/ \
  && sudo chmod 644 /etc/mysql/conf.d/*.cnf \
  "

  run_or_err "Starting MySQL" "sudo /etc/init.d/mysql start"
  run_or_err "Creating MySQL TestDB" "mysql -u root -e 'create database dbic_test;'"
  export DBICTEST_MYSQL_DSN='dbi:mysql:database=dbic_test;host=127.0.0.1'
  export DBICTEST_MYSQL_USER=root

### config pg
  run_or_err "Starting PostgreSQL" "sudo /etc/init.d/postgresql start"
  run_or_err "Creating PostgreSQL TestDB" "psql -c 'create database dbic_test;' -U postgres"
  export DBICTEST_PG_DSN='dbi:Pg:database=dbic_test;host=127.0.0.1'
  export DBICTEST_PG_USER=postgres

### conig firebird
  # poor man's deb config
  EXPECT_FB_SCRIPT='
    spawn dpkg-reconfigure --frontend=text firebird2.5-super
    expect "Enable Firebird server?"
    send "\177\177\177\177yes\r"
    expect "Password for SYSDBA"
    send "123\r"
    sleep 2
    expect eof
  '
  # creating testdb
  # FIXME - this step still fails from time to time >:(((
  # has to do with the FB reconfiguration I suppose
  # for now if it fails twice - simply skip FB testing
  for i in 1 2 3 ; do

    run_or_err "Re-configuring Firebird" "
      sync
      sleep 5
      DEBIAN_FRONTEND=text sudo $(which expect) -c '$EXPECT_FB_SCRIPT'
    "

    if run_or_err "Creating Firebird TestDB" \
      "echo \"CREATE DATABASE '/var/lib/firebird/2.5/data/dbic_test.fdb';\" | sudo isql-fb -u sysdba -p 123"
    then


      # Do not upgrade to a newer ODBC driver - smoking on an old
      # and buggy POS is much more valuable
      #
      run_or_err "Fetching and building Firebird ODBC driver" '
        cd "$(mktemp -d)"
        wget -qO- https://github.com/ribasushi/patchup-Firebird-ODBC-driver/archive/2.0.2.153.tar.gz | tar -zx --strip-components 1
        cd Builds/Gcc.lin
        perl -p -i -e "s|/usr/lib64|/usr/lib/x86_64-linux-gnu|g"                          ../makefile.environ
        perl -p -i -e "s|major\".\"minor\".\"buildnum|major \".\" minor \".\" buildnum|"  ../../SetupAttributes.h
      [[ -n "$ASAN_FLAGS_COMMON" ]] && \
        perl -p -i -e "s|^GCC\s*\=\s*g\+\+$|GCC = $CXX $ASAN_FLAGS_COMMON|"               makefile.linux
        make -f makefile.linux
        sudo make -f makefile.linux install
      '

      sudo bash -c 'cat >> /etc/odbcinst.ini' <<< "
[Firebird]
Description     = InterBase/Firebird ODBC Driver
Driver          = /usr/lib/x86_64-linux-gnu/libOdbcFb.so
Setup           = /usr/lib/x86_64-linux-gnu/libOdbcFb.so
Threading       = 1
FileUsage       = 1
"

      export DBICTEST_FIREBIRD_DSN=dbi:Firebird:dbname=/var/lib/firebird/2.5/data/dbic_test.fdb
      export DBICTEST_FIREBIRD_USER=SYSDBA
      export DBICTEST_FIREBIRD_PASS=123

      export DBICTEST_FIREBIRD_INTERBASE_DSN=dbi:InterBase:dbname=/var/lib/firebird/2.5/data/dbic_test.fdb
      export DBICTEST_FIREBIRD_INTERBASE_USER=SYSDBA
      export DBICTEST_FIREBIRD_INTERBASE_PASS=123

      export DBICTEST_FIREBIRD_ODBC_DSN="dbi:ODBC:Driver=Firebird;Dbname=/var/lib/firebird/2.5/data/dbic_test.fdb"
      export DBICTEST_FIREBIRD_ODBC_USER=SYSDBA
      export DBICTEST_FIREBIRD_ODBC_PASS=123

      break
    fi

  done

### config oracle
  SRV_ORA_HOME=/usr/lib/oracle/xe/app/oracle/product/10.2.0/server

  # without this some of the more zealous tests can exhaust the amount
  # of listeners and oracle is too slow to spin extras up :(
  sudo bash -c "echo -e '\nprocesses=150' >> $SRV_ORA_HOME/config/scripts/init.ora"

  EXPECT_ORA_SCRIPT='
    spawn /etc/init.d/oracle-xe configure

    sleep 1
    set send_slow {1 .005}

    expect "Specify the HTTP port that will be used for Oracle Application Express"
    sleep 0.5
    send -s "8021\r"

    expect "Specify a port that will be used for the database listener"
    sleep 0.5
    send -s "1521\r"

    expect "Specify a password to be used for database accounts"
    sleep 0.5
    send -s "adminpass\r"

    expect "Confirm the password"
    sleep 0.5
    send -s "adminpass\r"

    expect "Do you want Oracle Database 10g Express Edition to be started on boot"
    sleep 0.5
    send -s "n\r"

    sleep 0.5
    expect "Configuring Database"

    sleep 1
    expect eof
    wait
  '

  # if we do not redirect to some random file, but instead try to capture
  # into a var the way run_or_err does - everything hangs
  # FIXME: I couldn't figure it out after 3 hours of headdesking,
  # would be nice to know the reason eventually
  run_or_err "Configuring OracleXE" "sudo $(which expect) -c '$EXPECT_ORA_SCRIPT' &>/tmp/ora_configure_10.2.log"

  export DBICTEST_ORA_DSN=dbi:Oracle://localhost:1521/XE
  export DBICTEST_ORA_USER=dbic_test
  export DBICTEST_ORA_PASS=abc123456
  export DBICTEST_ORA_EXTRAUSER_DSN="$DBICTEST_ORA_DSN"
  export DBICTEST_ORA_EXTRAUSER_USER=dbic_test_extra
  export DBICTEST_ORA_EXTRAUSER_PASS=abc123456

  run_or_err "Create Oracle users" "ORACLE_SID=XE ORACLE_HOME=$SRV_ORA_HOME $SRV_ORA_HOME/bin/sqlplus -L -S system/adminpass @/dev/stdin <<< '
    CREATE USER $DBICTEST_ORA_USER IDENTIFIED BY $DBICTEST_ORA_PASS;
    GRANT connect,resource TO $DBICTEST_ORA_USER;
    CREATE USER $DBICTEST_ORA_EXTRAUSER_USER IDENTIFIED BY $DBICTEST_ORA_EXTRAUSER_PASS;
    GRANT connect,resource TO $DBICTEST_ORA_EXTRAUSER_USER;
  '"

  export ORACLE_HOME="$CACHE_DIR/poormanscache-OracleXE-10.2.0_deb_mixed/ora_instaclient/x86-64/oracle_instaclient_10.2.0.5.0"

### config db2exc
  # we may have skipped installation due to low memory
  if dpkg -l db2exc &>/dev/null ; then
    # WTF is this world-writable?
    # Strip the write bit so it doesn't trip Ubuntu's symlink-in-/tmp attack mitigation
    sudo chmod -R o-w ~dasusr1/das

    export DB2_HOME=/opt/ibm/db2/V9.7
    export DBICTEST_DB2_DSN=dbi:DB2:DATABASE=dbictest
    export DBICTEST_DB2_USER=db2inst1
    export DBICTEST_DB2_PASS=abc123456

    run_or_err "Set up DB2 users" \
      "echo -e '$DBICTEST_DB2_PASS\n$DBICTEST_DB2_PASS' | sudo passwd $DBICTEST_DB2_USER"

    run_or_err "Create DB2 database" \
      "sudo -u $DBICTEST_DB2_USER -i db2 'CREATE DATABASE dbictest' && sudo -u $DBICTEST_DB2_USER -i db2 'ACTIVATE DATABASE dbictest'"
  fi

fi
