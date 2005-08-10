use strict;
use warnings;
use DBICTest::Schema;

my $db_file = "t/var/DBIxClass.db";

unlink($db_file) if -e $db_file;
unlink($db_file . "-journal") if -e $db_file . "-journal";
mkdir("t/var") unless -d "t/var";

DBICTest::Schema->compose_connection('DBICTest' => "dbi:SQLite:${db_file}");

my $dbh = DBICTest::_db->storage->dbh;

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

1;
