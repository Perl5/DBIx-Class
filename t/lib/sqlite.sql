-- 
-- Created by SQL::Translator::Producer::SQLite
-- Created on Sun Nov 23 13:27:13 2008
-- 
BEGIN TRANSACTION;


--
-- Table: artist
--
CREATE TABLE artist (
  artistid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100),
  rank integer NOT NULL DEFAULT '13',
  charfield char(10)
);


--
-- Table: artist_undirected_map
--
CREATE TABLE artist_undirected_map (
  id1 integer NOT NULL,
  id2 integer NOT NULL,
  PRIMARY KEY (id1, id2)
);

CREATE INDEX artist_undirected_map_idx_id1_ ON artist_undirected_map (id1);
CREATE INDEX artist_undirected_map_idx_id2_ ON artist_undirected_map (id2);

--
-- Table: cd_artwork
--
CREATE TABLE cd_artwork (
  cd_id INTEGER PRIMARY KEY NOT NULL
);

CREATE INDEX cd_artwork_idx_cd_id_cd_artwor ON cd_artwork (cd_id);

--
-- Table: artwork_to_artist
--
CREATE TABLE artwork_to_artist (
  artwork_cd_id integer NOT NULL,
  artist_id integer NOT NULL,
  PRIMARY KEY (artwork_cd_id, artist_id)
);

CREATE INDEX artwork_to_artist_idx_artist_id_artwork_to_arti ON artwork_to_artist (artist_id);
CREATE INDEX artwork_to_artist_idx_artwork_cd_id_artwork_to_ ON artwork_to_artist (artwork_cd_id);

--
-- Table: bookmark
--
CREATE TABLE bookmark (
  id INTEGER PRIMARY KEY NOT NULL,
  link integer NOT NULL
);

CREATE INDEX bookmark_idx_link_bookmark ON bookmark (link);

--
-- Table: books
--
CREATE TABLE books (
  id INTEGER PRIMARY KEY NOT NULL,
  source varchar(100) NOT NULL,
  owner integer NOT NULL,
  title varchar(100) NOT NULL,
  price integer
);


--
-- Table: cd
--
CREATE TABLE cd (
  cdid INTEGER PRIMARY KEY NOT NULL,
  artist integer NOT NULL,
  title varchar(100) NOT NULL,
  year varchar(100) NOT NULL,
  genreid integer,
  single_track integer
);

CREATE INDEX cd_idx_artist_cd ON cd (artist);
CREATE INDEX cd_idx_genreid_cd ON cd (genreid);
CREATE INDEX cd_idx_single_track_cd ON cd (single_track);
CREATE UNIQUE INDEX cd_artist_title_cd ON cd (artist, title);

--
-- Table: cd_to_producer
--
CREATE TABLE cd_to_producer (
  cd integer NOT NULL,
  producer integer NOT NULL,
  PRIMARY KEY (cd, producer)
);

CREATE INDEX cd_to_producer_idx_cd_cd_to_pr ON cd_to_producer (cd);
CREATE INDEX cd_to_producer_idx_producer_cd ON cd_to_producer (producer);

--
-- Table: collection
--
CREATE TABLE collection (
  collectionid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100) NOT NULL
);


--
-- Table: collection_object
--
CREATE TABLE collection_object (
  collection integer NOT NULL,
  object integer NOT NULL,
  PRIMARY KEY (collection, object)
);

CREATE INDEX collection_object_idx_collection_collection_obj ON collection_object (collection);
CREATE INDEX collection_object_idx_object_c ON collection_object (object);

--
-- Table: employee
--
CREATE TABLE employee (
  employee_id INTEGER PRIMARY KEY NOT NULL,
  position integer NOT NULL,
  group_id integer,
  group_id_2 integer,
  name varchar(100)
);


--
-- Table: event
--
CREATE TABLE event (
  id INTEGER PRIMARY KEY NOT NULL,
  starts_at datetime NOT NULL,
  created_on timestamp NOT NULL,
  varchar_date varchar(20),
  varchar_datetime varchar(20),
  skip_inflation datetime
);


--
-- Table: file_columns
--
CREATE TABLE file_columns (
  id INTEGER PRIMARY KEY NOT NULL,
  file varchar(255) NOT NULL
);


--
-- Table: forceforeign
--
CREATE TABLE forceforeign (
  artist INTEGER PRIMARY KEY NOT NULL,
  cd integer NOT NULL
);

CREATE INDEX forceforeign_idx_artist_forcef ON forceforeign (artist);

--
-- Table: fourkeys
--
CREATE TABLE fourkeys (
  foo integer NOT NULL,
  bar integer NOT NULL,
  hello integer NOT NULL,
  goodbye integer NOT NULL,
  sensors character NOT NULL,
  PRIMARY KEY (foo, bar, hello, goodbye)
);


--
-- Table: fourkeys_to_twokeys
--
CREATE TABLE fourkeys_to_twokeys (
  f_foo integer NOT NULL,
  f_bar integer NOT NULL,
  f_hello integer NOT NULL,
  f_goodbye integer NOT NULL,
  t_artist integer NOT NULL,
  t_cd integer NOT NULL,
  autopilot character NOT NULL,
  PRIMARY KEY (f_foo, f_bar, f_hello, f_goodbye, t_artist, t_cd)
);

CREATE INDEX fourkeys_to_twokeys_idx_f_foo_f_bar_f_hello_f_goodbye_ ON fourkeys_to_twokeys (f_foo, f_bar, f_hello, f_goodbye);
CREATE INDEX fourkeys_to_twokeys_idx_t_artist_t_cd_fourkeys_to ON fourkeys_to_twokeys (t_artist, t_cd);

--
-- Table: genre
--
CREATE TABLE genre (
  genreid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100) NOT NULL
);

CREATE UNIQUE INDEX genre_name_genre ON genre (name);

--
-- Table: images
--
CREATE TABLE images (
  id INTEGER PRIMARY KEY NOT NULL,
  artwork_id integer NOT NULL,
  name varchar(100) NOT NULL,
  data blob
);

CREATE INDEX images_idx_artwork_id_images ON images (artwork_id);

--
-- Table: liner_notes
--
CREATE TABLE liner_notes (
  liner_id INTEGER PRIMARY KEY NOT NULL,
  notes varchar(100) NOT NULL
);

CREATE INDEX liner_notes_idx_liner_id_liner ON liner_notes (liner_id);

--
-- Table: link
--
CREATE TABLE link (
  id INTEGER PRIMARY KEY NOT NULL,
  url varchar(100),
  title varchar(100)
);


--
-- Table: lyric_versions
--
CREATE TABLE lyric_versions (
  id INTEGER PRIMARY KEY NOT NULL,
  lyric_id integer NOT NULL,
  text varchar(100) NOT NULL
);

CREATE INDEX lyric_versions_idx_lyric_id_ly ON lyric_versions (lyric_id);

--
-- Table: lyrics
--
CREATE TABLE lyrics (
  lyric_id INTEGER PRIMARY KEY NOT NULL,
  track_id integer NOT NULL
);

CREATE INDEX lyrics_idx_track_id_lyrics ON lyrics (track_id);

--
-- Table: noprimarykey
--
CREATE TABLE noprimarykey (
  foo integer NOT NULL,
  bar integer NOT NULL,
  baz integer NOT NULL
);

CREATE UNIQUE INDEX foo_bar_noprimarykey ON noprimarykey (foo, bar);

--
-- Table: onekey
--
CREATE TABLE onekey (
  id INTEGER PRIMARY KEY NOT NULL,
  artist integer NOT NULL,
  cd integer NOT NULL
);


--
-- Table: owners
--
CREATE TABLE owners (
  ownerid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100) NOT NULL
);


--
-- Table: producer
--
CREATE TABLE producer (
  producerid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100) NOT NULL
);

CREATE UNIQUE INDEX prod_name_producer ON producer (name);

--
-- Table: self_ref
--
CREATE TABLE self_ref (
  id INTEGER PRIMARY KEY NOT NULL,
  name varchar(100) NOT NULL
);


--
-- Table: self_ref_alias
--
CREATE TABLE self_ref_alias (
  self_ref integer NOT NULL,
  alias integer NOT NULL,
  PRIMARY KEY (self_ref, alias)
);

CREATE INDEX self_ref_alias_idx_alias_self_ ON self_ref_alias (alias);
CREATE INDEX self_ref_alias_idx_self_ref_se ON self_ref_alias (self_ref);

--
-- Table: sequence_test
--
CREATE TABLE sequence_test (
  pkid1 integer NOT NULL,
  pkid2 integer NOT NULL,
  nonpkid integer NOT NULL,
  name varchar(100),
  PRIMARY KEY (pkid1, pkid2)
);


--
-- Table: serialized
--
CREATE TABLE serialized (
  id INTEGER PRIMARY KEY NOT NULL,
  serialized text NOT NULL
);


--
-- Table: tags
--
CREATE TABLE tags (
  tagid INTEGER PRIMARY KEY NOT NULL,
  cd integer NOT NULL,
  tag varchar(100) NOT NULL
);

CREATE INDEX tags_idx_cd_tags ON tags (cd);

--
-- Table: track
--
CREATE TABLE track (
  trackid INTEGER PRIMARY KEY NOT NULL,
  cd integer NOT NULL,
  position integer NOT NULL,
  title varchar(100) NOT NULL,
  last_updated_on datetime
);

CREATE INDEX track_idx_cd_track ON track (cd);
CREATE UNIQUE INDEX track_cd_position_track ON track (cd, position);
CREATE UNIQUE INDEX track_cd_title_track ON track (cd, title);

--
-- Table: treelike
--
CREATE TABLE treelike (
  id INTEGER PRIMARY KEY NOT NULL,
  parent integer,
  name varchar(100) NOT NULL
);

CREATE INDEX treelike_idx_parent_treelike ON treelike (parent);

--
-- Table: twokeytreelike
--
CREATE TABLE twokeytreelike (
  id1 integer NOT NULL,
  id2 integer NOT NULL,
  parent1 integer NOT NULL,
  parent2 integer NOT NULL,
  name varchar(100) NOT NULL,
  PRIMARY KEY (id1, id2)
);

CREATE INDEX twokeytreelike_idx_parent1_parent2_twokeytre ON twokeytreelike (parent1, parent2);
CREATE UNIQUE INDEX tktlnameunique_twokeytreelike ON twokeytreelike (name);

--
-- Table: twokeys
--
CREATE TABLE twokeys (
  artist integer NOT NULL,
  cd integer NOT NULL,
  PRIMARY KEY (artist, cd)
);

CREATE INDEX twokeys_idx_artist_twokeys ON twokeys (artist);

--
-- Table: typed_object
--
CREATE TABLE typed_object (
  objectid INTEGER PRIMARY KEY NOT NULL,
  type varchar(100) NOT NULL,
  value varchar(100) NOT NULL
);


COMMIT;
