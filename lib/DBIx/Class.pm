package DBIx::Class;

use strict;
use warnings;

our $VERSION;
# Always remember to do all digits for the version even if they're 0
# i.e. first release of 0.XX *must* be 0.XX000. This avoids fBSD ports
# brain damage and presumably various other packaging systems too

# $VERSION declaration must stay up here, ahead of any other package
# declarations, as to not confuse various modules attempting to determine
# this ones version, whether that be s.c.o. or Module::Metadata, etc
$VERSION = '0.08270';

$VERSION = eval $VERSION if $VERSION =~ /_/; # numify for warning-free dev releases

use DBIx::Class::_Util;
use mro 'c3';

use DBIx::Class::Optional::Dependencies;

use base qw/DBIx::Class::Componentised DBIx::Class::AccessorGroup/;
use DBIx::Class::StartupCheck;
use DBIx::Class::Exception;

__PACKAGE__->mk_group_accessors(inherited => '_skip_namespace_frames');
__PACKAGE__->_skip_namespace_frames('^DBIx::Class|^SQL::Abstract|^Try::Tiny|^Class::Accessor::Grouped|^Context::Preserve');

sub mk_classdata {
  shift->mk_classaccessor(@_);
}

sub mk_classaccessor {
  my $self = shift;
  $self->mk_group_accessors('inherited', $_[0]);
  $self->set_inherited(@_) if @_ > 1;
}

sub component_base_class { 'DBIx::Class' }

sub MODIFY_CODE_ATTRIBUTES {
  my ($class,$code,@attrs) = @_;
  $class->mk_classdata('__attr_cache' => {})
    unless $class->can('__attr_cache');
  $class->__attr_cache->{$code} = [@attrs];
  return ();
}

sub _attr_cache {
  my $self = shift;
  my $cache = $self->can('__attr_cache') ? $self->__attr_cache : {};

  return {
    %$cache,
    %{ $self->maybe::next::method || {} },
  };
}

1;

__END__

=encoding UTF-8

=head1 NAME

DBIx::Class - Extensible and flexible object <-> relational mapper.

=head1 WHERE TO START READING

See L<DBIx::Class::Manual::DocMap> for an overview of the exhaustive documentation.
To get the most out of DBIx::Class with the least confusion it is strongly
recommended to read (at the very least) the
L<Manuals|DBIx::Class::Manual::DocMap/Manuals> in the order presented there.

=head1 HOW TO GET HELP

Due to the complexity of its problem domain, DBIx::Class is a relatively
complex framework. After you start using DBIx::Class questions will inevitably
arise. If you are stuck with a problem or have doubts about a particular
approach do not hesitate to contact the community with your questions. The
list below is sorted by "fastest response time":

=over

=item * IRC: irc.perl.org#dbix-class

=for html
<a href="https://chat.mibbit.com/#dbix-class@irc.perl.org">(click for instant chatroom login)</a>

=item * Mailing list: L<http://lists.scsys.co.uk/mailman/listinfo/dbix-class>

=item * RT Bug Tracker: L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=DBIx-Class>

=item * Twitter: L<https://www.twitter.com/dbix_class>

=item * Web Site: L<http://www.dbix-class.org/>

=back

=head1 SYNOPSIS

For the very impatient: L<DBIx::Class::Manual::QuickStart>

This code in the next step can be generated automatically from an existing
database, see L<dbicdump> from the distribution C<DBIx-Class-Schema-Loader>.

=head2 Schema classes preparation

Create a schema class called F<MyApp/Schema.pm>:

  package MyApp::Schema;
  use base qw/DBIx::Class::Schema/;

  __PACKAGE__->load_namespaces();

  1;

Create a result class to represent artists, who have many CDs, in
F<MyApp/Schema/Result/Artist.pm>:

See L<DBIx::Class::ResultSource> for docs on defining result classes.

  package MyApp::Schema::Result::Artist;
  use base qw/DBIx::Class::Core/;

  __PACKAGE__->table('artist');
  __PACKAGE__->add_columns(qw/ artistid name /);
  __PACKAGE__->set_primary_key('artistid');
  __PACKAGE__->has_many(cds => 'MyApp::Schema::Result::CD', 'artistid');

  1;

A result class to represent a CD, which belongs to an artist, in
F<MyApp/Schema/Result/CD.pm>:

  package MyApp::Schema::Result::CD;
  use base qw/DBIx::Class::Core/;

  __PACKAGE__->load_components(qw/InflateColumn::DateTime/);
  __PACKAGE__->table('cd');
  __PACKAGE__->add_columns(qw/ cdid artistid title year /);
  __PACKAGE__->set_primary_key('cdid');
  __PACKAGE__->belongs_to(artist => 'MyApp::Schema::Result::Artist', 'artistid');

  1;

=head2 API usage

Then you can use these classes in your application's code:

  # Connect to your database.
  use MyApp::Schema;
  my $schema = MyApp::Schema->connect($dbi_dsn, $user, $pass, \%dbi_params);

  # Query for all artists and put them in an array,
  # or retrieve them as a result set object.
  # $schema->resultset returns a DBIx::Class::ResultSet
  my @all_artists = $schema->resultset('Artist')->all;
  my $all_artists_rs = $schema->resultset('Artist');

  # Output all artists names
  # $artist here is a DBIx::Class::Row, which has accessors
  # for all its columns. Rows are also subclasses of your Result class.
  foreach $artist (@all_artists) {
    print $artist->name, "\n";
  }

  # Create a result set to search for artists.
  # This does not query the DB.
  my $johns_rs = $schema->resultset('Artist')->search(
    # Build your WHERE using an SQL::Abstract structure:
    { name => { like => 'John%' } }
  );

  # Execute a joined query to get the cds.
  my @all_john_cds = $johns_rs->search_related('cds')->all;

  # Fetch the next available row.
  my $first_john = $johns_rs->next;

  # Specify ORDER BY on the query.
  my $first_john_cds_by_title_rs = $first_john->cds(
    undef,
    { order_by => 'title' }
  );

  # Create a result set that will fetch the artist data
  # at the same time as it fetches CDs, using only one query.
  my $millennium_cds_rs = $schema->resultset('CD')->search(
    { year => 2000 },
    { prefetch => 'artist' }
  );

  my $cd = $millennium_cds_rs->next; # SELECT ... FROM cds JOIN artists ...
  my $cd_artist_name = $cd->artist->name; # Already has the data so no 2nd query

  # new() makes a Result object but doesnt insert it into the DB.
  # create() is the same as new() then insert().
  my $new_cd = $schema->resultset('CD')->new({ title => 'Spoon' });
  $new_cd->artist($cd->artist);
  $new_cd->insert; # Auto-increment primary key filled in after INSERT
  $new_cd->title('Fork');

  $schema->txn_do(sub { $new_cd->update }); # Runs the update in a transaction

  # change the year of all the millennium CDs at once
  $millennium_cds_rs->update({ year => 2002 });

=head1 DESCRIPTION

This is an SQL to OO mapper with an object API inspired by L<Class::DBI>
(with a compatibility layer as a springboard for porting) and a resultset API
that allows abstract encapsulation of database operations. It aims to make
representing queries in your code as perl-ish as possible while still
providing access to as many of the capabilities of the database as possible,
including retrieving related records from multiple tables in a single query,
C<JOIN>, C<LEFT JOIN>, C<COUNT>, C<DISTINCT>, C<GROUP BY>, C<ORDER BY> and
C<HAVING> support.

DBIx::Class can handle multi-column primary and foreign keys, complex
queries and database-level paging, and does its best to only query the
database in order to return something you've directly asked for. If a
resultset is used as an iterator it only fetches rows off the statement
handle as requested in order to minimise memory usage. It has auto-increment
support for SQLite, MySQL, PostgreSQL, Oracle, SQL Server and DB2 and is
known to be used in production on at least the first four, and is fork-
and thread-safe out of the box (although
L<your DBD may not be|DBI/Threads and Thread Safety>).

This project is still under rapid development, so large new features may be
marked B<experimental> - such APIs are still usable but may have edge bugs.
Failing test cases are I<always> welcome and point releases are put out rapidly
as bugs are found and fixed.

We do our best to maintain full backwards compatibility for published
APIs, since DBIx::Class is used in production in many organisations,
and even backwards incompatible changes to non-published APIs will be fixed
if they're reported and doing so doesn't cost the codebase anything.

The test suite is quite substantial, and several developer releases
are generally made to CPAN before the branch for the next release is
merged back to trunk for a major release.

=head1 HOW TO CONTRIBUTE

Contributions are always welcome, in all usable forms (we especially
welcome documentation improvements). The delivery methods include git-
or unified-diff formatted patches, GitHub pull requests, or plain bug
reports either via RT or the Mailing list. Contributors are generally
granted full access to the official repository after their first patch
passes successful review.

=for comment
FIXME: Getty, frew and jnap need to get off their asses and finish the contrib section so we can link it here ;)

This project is maintained in a git repository. The code and related tools are
accessible at the following locations:

=over

=item * Official repo: L<git://git.shadowcat.co.uk/dbsrgits/DBIx-Class.git>

=item * Official gitweb: L<http://git.shadowcat.co.uk/gitweb/gitweb.cgi?p=dbsrgits/DBIx-Class.git>

=item * GitHub mirror: L<https://github.com/dbsrgits/DBIx-Class>

=item * Authorized committers: L<ssh://dbsrgits@git.shadowcat.co.uk/DBIx-Class.git>

=item * Travis-CI log: L<https://travis-ci.org/dbsrgits/dbix-class/builds>

=for html
&#x21AA; Stable branch CI status: <img src="https://secure.travis-ci.org/dbsrgits/dbix-class.png?branch=master"></img>

=back

=head1 AUTHOR

mst: Matt S. Trout <mst@shadowcatsystems.co.uk>

(I mostly consider myself "project founder" these days but the AUTHOR heading
is traditional :)

=head1 CONTRIBUTORS

abraxxa: Alexander Hartmaier <abraxxa@cpan.org>

acca: Alexander Kuznetsov <acca@cpan.org>

aherzog: Adam Herzog <adam@herzogdesigns.com>

Alexander Keusch <cpan@keusch.at>

alexrj: Alessandro Ranellucci <aar@cpan.org>

alnewkirk: Al Newkirk <we@ana.im>

amiri: Amiri Barksdale <amiri@metalabel.com>

amoore: Andrew Moore <amoore@cpan.org>

andrewalker: Andre Walker <andre@andrewalker.net>

andyg: Andy Grundman <andy@hybridized.org>

ank: Andres Kievsky

arc: Aaron Crane <arc@cpan.org>

arcanez: Justin Hunter <justin.d.hunter@gmail.com>

ash: Ash Berlin <ash@cpan.org>

bert: Norbert Csongrádi <bert@cpan.org>

blblack: Brandon L. Black <blblack@gmail.com>

bluefeet: Aran Deltac <bluefeet@cpan.org>

bphillips: Brian Phillips <bphillips@cpan.org>

boghead: Bryan Beeley <cpan@beeley.org>

brd: Brad Davis <brd@FreeBSD.org>

bricas: Brian Cassidy <bricas@cpan.org>

brunov: Bruno Vecchi <vecchi.b@gmail.com>

caelum: Rafael Kitover <rkitover@cpan.org>

caldrin: Maik Hentsche <maik.hentsche@amd.com>

castaway: Jess Robinson

claco: Christopher H. Laco

clkao: CL Kao

da5id: David Jack Olrik <djo@cpan.org>

dariusj: Darius Jokilehto <dariusjokilehto@yahoo.co.uk>

davewood: David Schmidt <davewood@gmx.at>

daxim: Lars Dɪᴇᴄᴋᴏᴡ 迪拉斯 <daxim@cpan.org>

debolaz: Anders Nor Berle <berle@cpan.org>

dew: Dan Thomas <dan@godders.org>

dkubb: Dan Kubb <dan.kubb-cpan@onautopilot.com>

dnm: Justin Wheeler <jwheeler@datademons.com>

dpetrov: Dimitar Petrov <mitakaa@gmail.com>

dwc: Daniel Westermann-Clark <danieltwc@cpan.org>

dyfrgi: Michael Leuchtenburg <michael@slashhome.org>

edenc: Eden Cardim <edencardim@gmail.com>

ether: Karen Etheridge <ether@cpan.org>

felliott: Fitz Elliott <fitz.elliott@gmail.com>

freetime: Bill Moseley <moseley@hank.org>

frew: Arthur Axel "fREW" Schmidt <frioux@gmail.com>

goraxe: Gordon Irving <goraxe@cpan.org>

gphat: Cory G Watson <gphat@cpan.org>

Grant Street Group L<http://www.grantstreet.com/>

groditi: Guillermo Roditi <groditi@cpan.org>

Haarg: Graham Knop <haarg@haarg.org>

hobbs: Andrew Rodland <arodland@cpan.org>

ilmari: Dagfinn Ilmari MannsE<aring>ker <ilmari@ilmari.org>

initself: Mike Baas <mike@initselftech.com>

ironcamel: Naveed Massjouni <naveedm9@gmail.com>

jawnsy: Jonathan Yu <jawnsy@cpan.org>

jasonmay: Jason May <jason.a.may@gmail.com>

jesper: Jesper Krogh

jgoulah: John Goulah <jgoulah@cpan.org>

jguenther: Justin Guenther <jguenther@cpan.org>

jhannah: Jay Hannah <jay@jays.net>

jmac: Jason McIntosh <jmac@appleseed-sc.com>

jnapiorkowski: John Napiorkowski <jjn1056@yahoo.com>

jon: Jon Schutz <jjschutz@cpan.org>

jshirley: J. Shirley <jshirley@gmail.com>

kaare: Kaare Rasmussen

konobi: Scott McWhirter

littlesavage: Alexey Illarionov <littlesavage@orionet.ru>

lukes: Luke Saunders <luke.saunders@gmail.com>

marcus: Marcus Ramberg <mramberg@cpan.org>

mattlaw: Matt Lawrence

mattp: Matt Phillips <mattp@cpan.org>

michaelr: Michael Reddick <michael.reddick@gmail.com>

milki: Jonathan Chu <milki@rescomp.berkeley.edu>

mithaldu: Christian Walde <walde.christian@gmail.com>

mjemmeson: Michael Jemmeson <michael.jemmeson@gmail.com>

mstratman: Mark A. Stratman <stratman@gmail.com>

ned: Neil de Carteret

nigel: Nigel Metheringham <nigelm@cpan.org>

ningu: David Kamholz <dkamholz@cpan.org>

Nniuq: Ron "Quinn" Straight" <quinnfazigu@gmail.org>

norbi: Norbert Buchmuller <norbi@nix.hu>

nuba: Nuba Princigalli <nuba@cpan.org>

Numa: Dan Sully <daniel@cpan.org>

ovid: Curtis "Ovid" Poe <ovid@cpan.org>

oyse: E<Oslash>ystein Torget <oystein.torget@dnv.com>

paulm: Paul Makepeace

penguin: K J Cheetham

perigrin: Chris Prather <chris@prather.org>

peter: Peter Collingbourne <peter@pcc.me.uk>

Peter Siklósi <einon@einon.hu>

Peter Valdemar ME<oslash>rch <peter@morch.com>

phaylon: Robert Sedlacek <phaylon@dunkelheit.at>

plu: Johannes Plunien <plu@cpan.org>

Possum: Daniel LeWarne <possum@cpan.org>

quicksilver: Jules Bean

rafl: Florian Ragwitz <rafl@debian.org>

rainboxx: Matthias Dietrich <perl@rb.ly>

rbo: Robert Bohne <rbo@cpan.org>

rbuels: Robert Buels <rmb32@cornell.edu>

rdj: Ryan D Johnson <ryan@innerfence.com>

ribasushi: Peter Rabbitson <ribasushi@cpan.org>

rjbs: Ricardo Signes <rjbs@cpan.org>

robkinyon: Rob Kinyon <rkinyon@cpan.org>

Robert Olson <bob@rdolson.org>

moltar: Roman Filippov <romanf@cpan.org>

Sadrak: Felix Antonius Wilhelm Ostmann <sadrak@cpan.org>

sc_: Just Another Perl Hacker

scotty: Scotty Allen <scotty@scottyallen.com>

semifor: Marc Mims <marc@questright.com>

SineSwiper: Brendan Byrd <bbyrd@cpan.org>

solomon: Jared Johnson <jaredj@nmgi.com>

spb: Stephen Bennett <stephen@freenode.net>

Squeeks <squeek@cpan.org>

sszabo: Stephan Szabo <sszabo@bigpanda.com>

talexb: Alex Beamish <talexb@gmail.com>

tamias: Ronald J Kimball <rjk@tamias.net>

teejay : Aaron Trevena <teejay@cpan.org>

Todd Lipcon

Tom Hukins

tonvoon: Ton Voon <tonvoon@cpan.org>

triode: Pete Gamache <gamache@cpan.org>

typester: Daisuke Murase <typester@cpan.org>

victori: Victor Igumnov <victori@cpan.org>

wdh: Will Hawes

wesm: Wes Malone <wes@mitsi.com>

willert: Sebastian Willert <willert@cpan.org>

wreis: Wallace Reis <wreis@cpan.org>

xenoterracide: Caleb Cushing <xenoterracide@gmail.com>

yrlnry: Mark Jason Dominus <mjd@plover.com>

zamolxes: Bogdan Lucaciu <bogdan@wiz.ro>

Zefram: Andrew Main <zefram@fysh.org>

=head1 COPYRIGHT

Copyright (c) 2005 - 2011 the DBIx::Class L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms
as perl itself.
