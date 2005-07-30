package DBICTest;

use strict;
use warnings;
use base qw/DBIx::Class::Core/;

my $db_file = "t/var/DBIxClass.db";

unlink($db_file) if -e $db_file;
unlink($db_file . "-journal") if -e $db_file . "-journal";
mkdir("t/var") unless -d "t/var";

__PACKAGE__->connection("dbi:SQLite:${db_file}");

my $dbh = __PACKAGE__->_get_dbh;

my $sql = <<EOSQL;
CREATE TABLE artist (artistid INTEGER NOT NULL PRIMARY KEY, name VARCHAR);

CREATE TABLE cd (cdid INTEGER NOT NULL PRIMARY KEY, artist INTEGER NOT NULL,
                     title VARCHAR, year VARCHAR);

CREATE TABLE liner_notes (liner_id INTEGER NOT NULL PRIMARY KEY, notes VARCHAR);

CREATE TABLE track (trackid INTEGER NOT NULL PRIMARY KEY, cd INTEGER NOT NULL,
                       position INTEGER NOT NULL, title VARCHAR);

CREATE TABLE tags (tagid INTEGER NOT NULL PRIMARY KEY, cd INTEGER NOT NULL,
                      tag VARCHAR);

CREATE TABLE twokeys (artist INTEGER NOT NULL, cd INTEGER NOT NULL,
                      PRIMARY KEY (artist, cd) );

CREATE TABLE fourkeys (foo INTEGER NOT NULL, bar INTEGER NOT NULL,
                      hello INTEGER NOT NULL, goodbye INTEGER NOT NULL,
                      PRIMARY KEY (foo, bar, hello, goodbye) );

CREATE TABLE onekey (id INTEGER NOT NULL PRIMARY KEY,
                      artist INTEGER NOT NULL, cd INTEGER NOT NULL );

INSERT INTO artist (artistid, name) VALUES (1, 'Caterwauler McCrae');

INSERT INTO artist (artistid, name) VALUES (2, 'Random Boy Band');

INSERT INTO artist (artistid, name) VALUES (3, 'We Are Goth');

INSERT INTO cd (cdid, artist, title, year)
    VALUES (1, 1, "Spoonful of bees", 1999);

INSERT INTO cd (cdid, artist, title, year)
    VALUES (2, 1, "Forkful of bees", 2001);

INSERT INTO cd (cdid, artist, title, year)
    VALUES (3, 1, "Caterwaulin' Blues", 1997);

INSERT INTO cd (cdid, artist, title, year)
    VALUES (4, 2, "Generic Manufactured Singles", 2001);

INSERT INTO cd (cdid, artist, title, year)
    VALUES (5, 3, "Come Be Depressed With Us", 1998);

INSERT INTO liner_notes (liner_id, notes)
    VALUES (2, "Buy Whiskey!");

INSERT INTO liner_notes (liner_id, notes)
    VALUES (4, "Buy Merch!");

INSERT INTO liner_notes (liner_id, notes)
    VALUES (5, "Kill Yourself!");

INSERT INTO tags (tagid, cd, tag) VALUES (1, 1, "Blue");

INSERT INTO tags (tagid, cd, tag) VALUES (2, 2, "Blue");

INSERT INTO tags (tagid, cd, tag) VALUES (3, 3, "Blue");

INSERT INTO tags (tagid, cd, tag) VALUES (4, 5, "Blue");

INSERT INTO tags (tagid, cd, tag) VALUES (5, 2, "Cheesy");

INSERT INTO tags (tagid, cd, tag) VALUES (6, 4, "Cheesy");

INSERT INTO tags (tagid, cd, tag) VALUES (7, 5, "Cheesy");

INSERT INTO tags (tagid, cd, tag) VALUES (8, 2, "Shiny");

INSERT INTO tags (tagid, cd, tag) VALUES (9, 4, "Shiny");

INSERT INTO twokeys (artist, cd) VALUES (1, 1);

INSERT INTO twokeys (artist, cd) VALUES (1, 2);

INSERT INTO twokeys (artist, cd) VALUES (2, 2);

INSERT INTO fourkeys (foo, bar, hello, goodbye) VALUES (1, 2, 3, 4);

INSERT INTO fourkeys (foo, bar, hello, goodbye) VALUES (5, 4, 3, 6);

INSERT INTO onekey (id, artist, cd) VALUES (1, 1, 1);

INSERT INTO onekey (id, artist, cd) VALUES (2, 1, 2);

INSERT INTO onekey (id, artist, cd) VALUES (3, 2, 2);
EOSQL

$dbh->do($_) for split(/\n\n/, $sql);

package DBICTest::LinerNotes;

use base 'DBICTest';

DBICTest::LinerNotes->table('liner_notes');
DBICTest::LinerNotes->add_columns(qw/liner_id notes/);
DBICTest::LinerNotes->set_primary_key('liner_id');

package DBICTest::Tag;

use base 'DBICTest';

DBICTest::Tag->table('tags');
DBICTest::Tag->add_columns(qw/tagid cd tag/);
DBICTest::Tag->set_primary_key('tagid');
#DBICTest::Tag->has_a(cd => 'SweetTest::CD');

package DBICTest::Track;

use base 'DBICTest';

DBICTest::Track->table('track');
DBICTest::Track->add_columns(qw/trackid cd position title/);
DBICTest::Track->set_primary_key('trackid');
#DBICTest::Track->has_a(cd => 'SweetTest::CD');

package DBICTest::CD;

use base 'DBICTest';

DBICTest::CD->table('cd');
DBICTest::CD->add_columns(qw/cdid artist title year/);
DBICTest::CD->set_primary_key('trackid');

#DBICTest::CD->has_many(tracks => 'SweetTest::Track');
#DBICTest::CD->has_many(tags => 'SweetTest::Tag');
#DBICTest::CD->has_a(artist => 'SweetTest::Artist');

#DBICTest::CD->might_have(liner_notes => 'SweetTest::LinerNotes' => qw/notes/);

package DBICTest::Artist;

use base 'DBICTest';

DBICTest::Artist->table('artist');
DBICTest::Artist->add_columns(qw/artistid name/);
DBICTest::Artist->set_primary_key('artistid');
#DBICTest::Artist->has_many(cds => 'SweetTest::CD');
#DBICTest::Artist->has_many(twokeys => 'SweetTest::TwoKeys');
#DBICTest::Artist->has_many(onekeys => 'SweetTest::OneKey');

package DBICTest::TwoKeys;

use base 'DBICTest';

DBICTest::TwoKeys->table('twokeys');
DBICTest::TwoKeys->add_columns(qw/artist cd/);
DBICTest::TwoKeys->set_primary_key(qw/artist cd/);
#DBICTest::TwoKeys->has_a(artist => 'SweetTest::Artist');
#DBICTest::TwoKeys->has_a(cd => 'SweetTest::CD');

package DBICTest::FourKeys;

use base 'DBICTest';

DBICTest::FourKeys->table('fourkeys');
DBICTest::FourKeys->add_columns(qw/foo bar hello goodbye/);
DBICTest::FourKeys->set_primary_key(qw/foo bar hello goodbye/);

package DBICTest::OneKey;

use base 'DBICTest';

DBICTest::OneKey->table('onekey');
DBICTest::OneKey->add_columns(qw/id artist cd/);
DBICTest::OneKey->set_primary_key('id');

1;
