#!/bin/bash

set -e

[[ -e Makefile.PL ]] || ( echo "Not in the right dir" && exit 1 )

clear
echo

export TRAVIS=true
export TRAVIS_REPO_SLUG="x/DBIx-Class"
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
    echo -n "$var "
  fi
done
echo -e "\n\n^^ variables above **automatically** set to '1'"

provecmd="nice prove -QlrswTj10"

echo -e "
Executing \`$provecmd $@\` via $(which perl) within the following environment:

$(env | grep -P 'TEST|HARNESS|MAKE|TRAVIS|PERL|DBIC|PATH|SHELL' | LC_ALL=C sort | cat -v)
"

$provecmd "$@"
