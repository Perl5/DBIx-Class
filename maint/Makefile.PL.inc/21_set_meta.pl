# principal author list is kinda mandated by spec, luckily is rather static
author 'mst: Matt S Trout <mst@shadowcat.co.uk> (project founder - original idea, architecture and implementation)';
author 'castaway: Jess Robinson <castaway@desert-island.me.uk> (lions share of the reference documentation and manuals)';
author 'ribasushi: Peter Rabbitson <ribasushi@leporine.io> (present day maintenance and controlled evolution)';

# pause sanity
Meta->{values}{x_authority} = 'cpan:RIBASUSHI';

# !!!experimental!!!
#
# <ribasushi> am wondering if an x_parallel_test => 1 and x_parallel_depchain_test => 1 would be of use in meta
# <ribasushi> to signify "project keeps tabs on itself and depchain to be in good health wrt running tests in parallel"
# <ribasushi> and having cpan(m) tack a -j6 automatically for that
# <ribasushi> it basically allows you to first consider any "high level intermediate dist" advertising "all my stuff works" so that larger swaths of CPAN get installed first under parallel
# <ribasushi> note - this is not "spur of the moment" - I first started testing my depchain in parallel 3 years ago
# <ribasushi> and have had it stable ( religiously tested on travis on any commit ) for about 2 years now
#
Meta->{values}{x_parallel_test_certified} = 1;
Meta->{values}{x_dependencies_parallel_test_certified} = 1;

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
resources 'repository'  => 'https://github.com/Perl5/DBIx-Class';
resources 'bugtracker'  => 'https://rt.cpan.org/Public/Dist/Display.html?Name=DBIx-Class';

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
/);

# keep the Makefile.PL eval happy
1;
