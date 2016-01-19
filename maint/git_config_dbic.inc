[remote "ghpr"]
  url = https://github.com/dbsrgits/DBIx-Class
  pushurl = DISALLOWED
  fetch = +refs/pull/*/head:refs/remotes/ghpr/*

[remote "historic"]
  url = git://git.shadowcat.co.uk/dbsrgits/DBIx-Class-Historic.git
  pushurl = ssh://dbsrgits@git.shadowcat.co.uk/DBIx-Class-Historic.git
  fetch = +refs/heads/*:refs/remotes/historic/*

[remote "debian"]
  url = git://anonscm.debian.org/pkg-perl/packages/libdbix-class-perl.git
  pushurl = DISALLOWED
  fetch = +refs/heads/master:refs/remotes/debian/master
  tagopt = --no-tags

[alias]
  # Lines after gitk in order:
  #
  # --exclude all refs matching the for loop
  # all known refs (branches/tags) excepth what we excluded
  # add all individual stashes
  # add all github PR heads without a matching historic/ghpr/* entry
  #
  # the /bin/true at the end is there to eat away any args to 'vis'
  # ( otherwise they will be treated as commands to execute after the & )
  vis = "!gitk \
    $( for r in historic/ghpr ghpr debian ; do echo "--exclude=refs/remotes/$r/*" ; done ) \
    --all \
    $(git stash list | cut -f 1 -d ':') \
    $(/bin/bash -c \"/usr/bin/comm -23 \
      <(git for-each-ref --sort=objectname --format='%(objectname:short)' refs/remotes/ghpr/ ) \
      <(git for-each-ref --sort=objectname --format='%(objectname:short)' refs/remotes/historic/ghpr/ refs/remotes/origin/ ) \
    \") \
  \"$@\" & /bin/true"


  # same but only for GitHub PRs
  prvis = "!gitk \
    $(/bin/bash -c \"/usr/bin/comm -23 \
      <(git for-each-ref --sort=objectname --format='%(objectname:short)' refs/remotes/ghpr/ ) \
      <(git for-each-ref --sort=objectname --format='%(objectname:short)' refs/remotes/historic/ghpr/ refs/remotes/origin/ ) \
    \") \
  \"$@\" & /bin/true"
