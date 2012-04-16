print "Appending to the no_index META list\n";

# Deprecated/internal modules need no exposure when building the meta
no_index directory => $_ for (qw|
  lib/DBIx/Class/Admin
  lib/DBIx/Class/PK/Auto
  lib/DBIx/Class/CDBICompat
|);
no_index package => $_ for (qw/
  DBIx::Class::Storage::DBIHacks
  DBIx::Class::Carp
  DBIx::Class::ResultSet::Pager
/);

# keep the Makefile.PL eval happy
1;
