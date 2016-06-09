#!/bin/bash

set -e

[[ -e Makefile.PL ]] || ( echo "Not in the right dir" && exit 1 )

clear
echo

export TRAVIS=true
export TRAVIS_REPO_SLUG="x/dbix-class"
export DBI_DSN="dbi:ODBC:server=NonexistentServerAddress"
export DBI_DRIVER="ADO"

toggle_booleans=( \
  $( grep -ohP '\bDBIC_[0-9_A-Z]+' -r lib/ --exclude-dir Optional | sort -u | grep -vP '^(DBIC_TRACE(_PROFILE)?|DBIC_.+_DEBUG)$' ) \
  DBIC_SHUFFLE_UNORDERED_RESULTSETS \
  DBICTEST_ASSERT_NO_SPURIOUS_EXCEPTION_ACTION \
  DBICTEST_RUN_ALL_TESTS \
  DBICTEST_SQLITE_REVERSE_DEFAULT_ORDER \
)

for var in "${toggle_booleans[@]}"
do
  if [[ -z "${!var}" ]] ; then
    export $var=1
    echo "POISON_ENV: setting $var to 1"
  fi
done

provecmd="nice prove -QlrswTj10"

echo -e "\nExecuting \`$provecmd\` via $(which perl)\n"
$provecmd
