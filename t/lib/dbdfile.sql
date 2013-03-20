CREATE TABLE artist (
  artistid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100),
  rank integer NOT NULL,
  charfield char(10)
);

CREATE TABLE collection (
  collectionid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100) NOT NULL
);

CREATE TABLE encoded (
  id INTEGER PRIMARY KEY NOT NULL,
  encoded varchar(100)
);

CREATE TABLE event (
  id INTEGER PRIMARY KEY NOT NULL,
  starts_at varchar(20) NOT NULL,
  created_on varchar(20) NOT NULL,
  varchar_date varchar(20),
  varchar_datetime varchar(20),
  skip_inflation varchar(20),
  ts_without_tz varchar(20)
);

CREATE TABLE fourkeys (
  foo integer NOT NULL,
  bar integer NOT NULL,
  hello integer NOT NULL,
  goodbye integer NOT NULL,
  sensors char(10) NOT NULL,
  read_count int,
  PRIMARY KEY (foo, bar, hello, goodbye)
);

CREATE TABLE genre (
  genreid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100) NOT NULL
);

CREATE TABLE images (
  id INTEGER PRIMARY KEY NOT NULL,
  artwork_id integer NOT NULL,
  name varchar(100) NOT NULL,
  data blob
);

CREATE TABLE link (
  id INTEGER PRIMARY KEY NOT NULL,
  url varchar(100),
  title varchar(100)
);

CREATE TABLE noprimarykey (
  foo integer NOT NULL,
  bar integer NOT NULL,
  baz integer NOT NULL
);

CREATE TABLE onekey (
  id INTEGER PRIMARY KEY NOT NULL,
  artist integer NOT NULL,
  cd integer NOT NULL
);

CREATE TABLE owners (
  id INTEGER PRIMARY KEY NOT NULL,
  name varchar(100) NOT NULL
);

CREATE TABLE producer (
  producerid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100) NOT NULL
);

CREATE TABLE self_ref (
  id INTEGER PRIMARY KEY NOT NULL,
  name varchar(100) NOT NULL
);

CREATE TABLE sequence_test (
  pkid1 integer NOT NULL,
  pkid2 integer NOT NULL,
  nonpkid integer NOT NULL,
  name varchar(100),
  PRIMARY KEY (pkid1, pkid2)
);

CREATE TABLE serialized (
  id INTEGER PRIMARY KEY NOT NULL,
  serialized text NOT NULL
);

CREATE TABLE treelike (
  id INTEGER PRIMARY KEY NOT NULL,
  parent integer,
  name varchar(100) NOT NULL,

);

CREATE TABLE twokeytreelike (
  id1 integer NOT NULL,
  id2 integer NOT NULL,
  parent1 integer NOT NULL,
  parent2 integer NOT NULL,
  name varchar(100) NOT NULL,
  PRIMARY KEY (id1, id2),

);

CREATE TABLE typed_object (
  objectid INTEGER PRIMARY KEY NOT NULL,
  type varchar(100) NOT NULL,
  value varchar(100) NOT NULL
);

CREATE TABLE artist_undirected_map (
  id1 integer NOT NULL,
  id2 integer NOT NULL,
  PRIMARY KEY (id1, id2),


);

CREATE TABLE artwork_to_artist (
  artwork_cd_id integer NOT NULL,
  artist_id integer NOT NULL,
  PRIMARY KEY (artwork_cd_id, artist_id),

);

CREATE TABLE bookmark (
  id INTEGER PRIMARY KEY NOT NULL,
  link integer,

);

CREATE TABLE books (
  id INTEGER PRIMARY KEY NOT NULL,
  source varchar(100) NOT NULL,
  owner integer NOT NULL,
  title varchar(100) NOT NULL,
  price integer,

);

CREATE TABLE employee (
  employee_id INTEGER PRIMARY KEY NOT NULL,
  position integer NOT NULL,
  group_id integer,
  group_id_2 integer,
  group_id_3 integer,
  name varchar(100),
  encoded integer,

);

CREATE TABLE forceforeign (
  artist INTEGER PRIMARY KEY NOT NULL,
  cd integer NOT NULL,

);

CREATE TABLE self_ref_alias (
  self_ref integer NOT NULL,
  alias integer NOT NULL,
  PRIMARY KEY (self_ref, alias),


);

CREATE TABLE track (
  trackid INTEGER PRIMARY KEY NOT NULL,
  cd integer NOT NULL,
  position int NOT NULL,
  title varchar(100) NOT NULL,
  last_updated_on varchar(20),
  last_updated_at varchar(20),

);

CREATE TABLE cd (
  cdid INTEGER PRIMARY KEY NOT NULL,
  artist integer NOT NULL,
  title varchar(100) NOT NULL,
  year varchar(100) NOT NULL,
  genreid integer,
  single_track integer,



);

CREATE TABLE collection_object (
  collection integer NOT NULL,
  object integer NOT NULL,
  PRIMARY KEY (collection, object),


);

CREATE TABLE lyrics (
  lyric_id INTEGER PRIMARY KEY NOT NULL,
  track_id integer NOT NULL,

);

CREATE TABLE liner_notes (
  liner_id INTEGER PRIMARY KEY NOT NULL,
  notes varchar(100) NOT NULL,

);

CREATE TABLE lyric_versions (
  id INTEGER PRIMARY KEY NOT NULL,
  lyric_id integer NOT NULL,
  texta varchar(100) NOT NULL,

);

CREATE TABLE tags (
  tagid INTEGER PRIMARY KEY NOT NULL,
  cd integer NOT NULL,
  tag varchar(100) NOT NULL,

);

CREATE TABLE cd_to_producer (
  cd integer NOT NULL,
  producer integer NOT NULL,
  attribute integer,
  PRIMARY KEY (cd, producer),


);

CREATE TABLE twokeys (
  artist integer NOT NULL,
  cd integer NOT NULL,
  PRIMARY KEY (artist, cd),


);

CREATE TABLE fourkeys_to_twokeys (
  f_foo integer NOT NULL,
  f_bar integer NOT NULL,
  f_hello integer NOT NULL,
  f_goodbye integer NOT NULL,
  t_artist integer NOT NULL,
  t_cd integer NOT NULL,
  autopilot char NOT NULL,
  pilot_sequence integer,
  PRIMARY KEY (f_foo, f_bar, f_hello, f_goodbye, t_artist, t_cd),


);
