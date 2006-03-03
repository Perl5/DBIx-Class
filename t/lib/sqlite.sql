-- 
-- Created by SQL::Translator::Producer::SQLite
-- Created on Mon Feb  6 01:07:16 2006
-- 
BEGIN TRANSACTION;

--
-- Table: twokeys
--
CREATE TABLE twokeys (
  artist integer NOT NULL,
  cd integer NOT NULL,
  PRIMARY KEY (artist, cd)
);

--
-- Table: cd_to_producer
--
CREATE TABLE cd_to_producer (
  cd integer NOT NULL,
  producer integer NOT NULL,
  PRIMARY KEY (cd, producer)
);

--
-- Table: liner_notes
--
CREATE TABLE liner_notes (
  liner_id INTEGER PRIMARY KEY NOT NULL,
  notes varchar NOT NULL
);

--
-- Table: artist
--
CREATE TABLE artist (
  artistid INTEGER PRIMARY KEY NOT NULL,
  name varchar
);

--
-- Table: self_ref_alias
--
CREATE TABLE self_ref_alias (
  self_ref integer NOT NULL,
  alias integer NOT NULL,
  PRIMARY KEY (self_ref, alias)
);

--
-- Table: fourkeys
--
CREATE TABLE fourkeys (
  foo integer NOT NULL,
  bar integer NOT NULL,
  hello integer NOT NULL,
  goodbye integer NOT NULL,
  PRIMARY KEY (foo, bar, hello, goodbye)
);

--
-- Table: cd
--
CREATE TABLE cd (
  cdid INTEGER PRIMARY KEY NOT NULL,
  artist integer NOT NULL,
  title varchar NOT NULL,
  year varchar NOT NULL
);

--
-- Table: artist_undirected_map
--
CREATE TABLE artist_undirected_map (
  id1 integer NOT NULL,
  id2 integer NOT NULL,
  PRIMARY KEY (id1, id2)
);

--
-- Table: producer
--
CREATE TABLE producer (
  producerid INTEGER PRIMARY KEY NOT NULL,
  name varchar NOT NULL
);

--
-- Table: onekey
--
CREATE TABLE onekey (
  id INTEGER PRIMARY KEY NOT NULL,
  artist integer NOT NULL,
  cd integer NOT NULL
);

--
-- Table: track
--
CREATE TABLE track (
  trackid INTEGER PRIMARY KEY NOT NULL,
  cd integer NOT NULL,
  position integer NOT NULL,
  title varchar NOT NULL
);

--
-- Table: treelike
--
CREATE TABLE treelike (
  id INTEGER PRIMARY KEY NOT NULL,
  parent integer NOT NULL,
  name varchar NOT NULL
);

--
-- Table: tags
--
CREATE TABLE tags (
  tagid varchar NOT NULL,
  cd integer NOT NULL,
  tag varchar NOT NULL,
  PRIMARY KEY (tagid)
);

--
-- Table: self_ref
--
CREATE TABLE self_ref (
  id INTEGER PRIMARY KEY NOT NULL,
  name varchar NOT NULL
);

--
-- Table: serialized
--
CREATE TABLE serialized (
    id INTEGER PRIMARY KEY NOT NULL,
    serialized text NOT NULL
);

COMMIT;
