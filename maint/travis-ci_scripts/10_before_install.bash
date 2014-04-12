#!/bin/bash

source maint/travis-ci_scripts/common.bash
if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

# Different boxes we run on may have different amount of hw threads
# Hence why we need to query
# Originally we used to read /sys/devices/system/cpu/online
# but it is not available these days (odd). Thus we fall to
# the alwas-present /proc/cpuinfo
# The oneliner is a tad convoluted - basicaly what we do is
# slurp the entire file and get the index off the last
# `processor    : XX` line
export NUMTHREADS="$(( $(perl -0777 -n -e 'print (/ (?: .+ ^ processor \s+ : \s+ (\d+) ) (?! ^ processor ) /smx)' < /proc/cpuinfo) + 1 ))"

export CACHE_DIR="/tmp/poormanscache"

# install some common tools from APT, more below unless CLEANTEST
apt_install libapp-nopaste-perl tree apt-transport-https

# FIXME - the debian package is oddly broken - uses a bin/env based shebang
# so nothing works under a brew. Fix here until #debian-perl patches it up
sudo /usr/bin/perl -p -i -e 's|#!/usr/bin/env perl|#!/usr/bin/perl|' $(which nopaste)

if [[ "$CLEANTEST" != "true" ]]; then
### apt-get invocation - faster to grab everything at once
  #
  # FIXME these debconf lines should automate the firebird config but do not :(((
  sudo bash -c 'echo -e "firebird2.5-super\tshared/firebird/enabled\tboolean\ttrue" | debconf-set-selections'
  sudo bash -c 'echo -e "firebird2.5-super\tshared/firebird/sysdba_password/new_password\tpassword\t123" | debconf-set-selections'

  # add extra APT repo for Oracle
  # (https is critical - apt-get update can't seem to follow the 302)
  sudo bash -c 'echo -e "\ndeb [arch=i386] https://oss.oracle.com/debian unstable main non-free" >> /etc/apt/sources.list'

  run_or_err "Cloning poor man's cache from github" "git clone --depth=1 --branch=poor_mans_travis_cache https://github.com/ribasushi/travis_futzing.git $CACHE_DIR && $CACHE_DIR/reassemble"

  run_or_err "Priming up the APT cache with $(echo $(ls -d $CACHE_DIR/apt_cache/*.deb))" "sudo cp $CACHE_DIR/apt_cache/*.deb /var/cache/apt/archives"

  apt_install memcached firebird2.5-super firebird2.5-dev unixodbc-dev expect oracle-xe

### config memcached
  run_or_err "Starting memcached" "sudo /etc/init.d/memcached start"
  export DBICTEST_MEMCACHED=127.0.0.1:11211

### config mysql
  run_or_err "Creating MySQL TestDB" "mysql -e 'create database dbic_test;'"
  export DBICTEST_MYSQL_DSN='dbi:mysql:database=dbic_test;host=127.0.0.1'
  export DBICTEST_MYSQL_USER=root

### config pg
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
    sleep 1
    expect eof
  '
  # creating testdb
  # FIXME - this step still fails from time to time >:(((
  # has to do with the FB reconfiguration I suppose
  # for now if it fails twice - simply skip FB testing
  for i in 1 2 ; do

    run_or_err "Re-configuring Firebird" "
      sync
      DEBIAN_FRONTEND=text sudo expect -c '$EXPECT_FB_SCRIPT'
      sleep 1
      sync
      # restart the server for good measure
      sudo /etc/init.d/firebird2.5-super stop || true
      sleep 1
      sync
      sudo /etc/init.d/firebird2.5-super start
      sleep 1
      sync
    "

    if run_or_err "Creating Firebird TestDB" \
      "echo \"CREATE DATABASE '/var/lib/firebird/2.5/data/dbic_test.fdb';\" | sudo isql-fb -u sysdba -p 123"
    then

      run_or_err "Fetching and building Firebird ODBC driver" '
        cd "$(mktemp -d)"
        wget -qO- http://sourceforge.net/projects/firebird/files/firebird-ODBC-driver/2.0.2-Release/OdbcFb-Source-2.0.2.153.gz/download | tar -zx
        cd Builds/Gcc.lin
        perl -p -i -e "s|/usr/lib64|/usr/lib/x86_64-linux-gnu|g" ../makefile.environ
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

  export ORACLE_HOME="$CACHE_DIR/ora_instaclient/x86-64/oracle_instaclient_10.2.0.5.0"
fi
