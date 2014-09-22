# authorshipz
author 'mst: Matt S. Trout <mst@shadowcat.co.uk>';
Meta->{values}{x_authority} = 'cpan:RIBASUSHI';

# legalese
license 'perl';
resources 'license' => 'http://dev.perl.org/licenses/';

# misc resources
abstract_from 'lib/DBIx/Class.pm';
resources 'homepage'    => 'http://www.dbix-class.org/';
resources 'IRC'         => 'irc://irc.perl.org/#dbix-class';
resources 'repository'  => 'https://github.com/dbsrgits/DBIx-Class';
resources 'MailingList' => 'http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/dbix-class';
resources 'bugtracker'  => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=DBIx-Class';

# nothing determined at runtime, except for possibly SQLT dep
# (see the check around DBICTEST_SQLT_DEPLOY in Makefile.PL)
dynamic_config 0;

# Deprecated/internal modules need no exposure when building the meta
no_index directory => $_ for (qw|
  lib/DBIx/Class/Admin
  lib/DBIx/Class/PK/Auto
  lib/DBIx/Class/CDBICompat
  maint
|);
no_index package => $_ for (qw/
  DBIx::Class::Storage::DBIHacks
  DBIx::Class::Storage::BlockRunner
  DBIx::Class::Carp
  DBIx::Class::_Util
  DBIx::Class::ResultSet::Pager
/);

# keep the Makefile.PL eval happy
1;
