#!/bin/bash

source maint/travis-ci_scripts/common.bash
if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

if [[ -n "$BREWVER" ]] ; then
  # .travis.yml already restricts branches to master, topic/* and smoke/*
  # do some extra short-circuiting here

  # when smoking master do not attempt bleadperl (not release-critical)
  if [[ "$TRAVIS_BRANCH" = "master" ]] && [[ "$BREWVER" = "blead" ]]; then
    echo_err "$(tstamp) master branch is not smoked with bleadperl - bailing out"
    export SHORT_CIRCUIT_SMOKE=1
  # on topic/ branches test only with travis perls
  elif [[ "$TRAVIS_BRANCH" =~ "topic/" ]]; then
    echo_err "$(tstamp) non-smoke branch and custom perl compilation requested - bailing out"
    export SHORT_CIRCUIT_SMOKE=1
  fi

  if [[ -n "$SHORT_CIRCUIT_SMOKE" ]]; then
    sleep 20  # give the console time to attach, otherwise it hangs
    return  # this is like an `exit 0` in sourcing
  fi
fi

# different boxes we run on may have different amount of hw threads
# hence why we need to query
# result is 1.5 times the physical threads
export NUMTHREADS=$(( ( $(cut -f 2 -d '-' /sys/devices/system/cpu/online) + 1 ) * 15 / 10  ))

if [[ "$CLEANTEST" != "true" ]]; then
### apt-get invocation - faster to grab everything at once
  #
  # FIXME these debconf lines should automate the firebird config but do not :(((
  sudo bash -c 'echo -e "firebird2.5-super\tshared/firebird/enabled\tboolean\ttrue" | debconf-set-selections'
  sudo bash -c 'echo -e "firebird2.5-super\tshared/firebird/sysdba_password/new_password\tpassword\t123" | debconf-set-selections'

  APT_PACKAGES="memcached firebird2.5-super firebird2.5-dev expect"
  run_or_err "Installing packages ($APT_PACKAGES)" "sudo apt-get install --allow-unauthenticated -y $APT_PACKAGES"

### config memcached
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
    wait
    sleep 1
  '
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

  # creating testdb
  # FIXME - this step still fails from time to time >:(((
  # has to do with the FB reconfiguration I suppose
  # for now if it fails - simply skip FB testing
  if run_or_err "Creating Firebird TestDB" \
    "echo \"CREATE DATABASE '/var/lib/firebird/2.5/data/dbic_test.fdb';\" | sudo isql-fb -u sysdba -p 123"
  then
    export DBICTEST_FIREBIRD_DSN=dbi:Firebird:dbname=/var/lib/firebird/2.5/data/dbic_test.fdb
    export DBICTEST_FIREBIRD_USER=SYSDBA
    export DBICTEST_FIREBIRD_PASS=123

    export DBICTEST_FIREBIRD_INTERBASE_DSN=dbi:InterBase:dbname=/var/lib/firebird/2.5/data/dbic_test.fdb
    export DBICTEST_FIREBIRD_INTERBASE_USER=SYSDBA
    export DBICTEST_FIREBIRD_INTERBASE_PASS=123
  fi

### oracle
  # FIXME: todo
  #DBICTEST_ORA_DSN=dbi:Oracle:host=localhost;sid=XE
  #DBICTEST_ORA_USER=dbic_test
  #DBICTEST_ORA_PASS=123
  #DBICTEST_ORA_EXTRAUSER_DSN=dbi:Oracle:host=localhost;sid=XE
  #DBICTEST_ORA_EXTRAUSER_USER=dbic_test_extra
  #DBICTEST_ORA_EXTRAUSER_PASS=123
  #ORACLE_HOME=/usr/lib/oracle/xe/app/oracle/product/10.2.0/client
fi
