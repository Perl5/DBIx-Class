# principal author list is kinda mandated by spec, luckily is rather static
author 'mst: Matt S Trout <mst@shadowcat.co.uk> (project founder - original idea, architecture and implementation)';
author 'castaway: Jess Robinson <castaway@desert-island.me.uk> (lions share of the reference documentation and manuals)';
author 'ribasushi: Peter Rabbitson <ribasushi@cpan.org> (present day maintenance and controlled evolution)';

# pause sanity
Meta->{values}{x_authority} = 'cpan:RIBASUSHI';

# populate x_contributors
# a direct dump of the sort is ok - xt/authors.t guarantees source sanity
Meta->{values}{x_contributors} = [ do {
  # according to #p5p this is how one safely reads random unicode
  # this set of boilerplate is insane... wasn't perl unicode-king...?
  no warnings 'once';
  require Encode;
  require PerlIO::encoding;
  local $PerlIO::encoding::fallback = Encode::FB_CROAK();

  open (my $fh, '<:encoding(UTF-8)', 'AUTHORS') or die "Unable to open AUTHORS - can't happen: $!\n";
  map { chomp; ( (! $_ or $_ =~ /^\s*\#/) ? () : $_ ) } <$fh>;

}];

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
