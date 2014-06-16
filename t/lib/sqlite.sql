CREATE TABLE "artist" (
  "artistid" INTEGER PRIMARY KEY NOT NULL,
  "name" varchar(100),
  "rank" integer NOT NULL DEFAULT 13,
  "charfield" char(10)
);

CREATE INDEX "artist_name_hookidx" ON "artist" ("name");

CREATE UNIQUE INDEX "artist_name" ON "artist" ("name");

CREATE UNIQUE INDEX "u_nullable" ON "artist" ("charfield", "rank");

CREATE TABLE "bindtype_test" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "bytea" blob,
  "blob" blob,
  "clob" clob,
  "a_memo" memo
);

CREATE TABLE "collection" (
  "collectionid" INTEGER PRIMARY KEY NOT NULL,
  "name" varchar(100) NOT NULL
);

CREATE TABLE "encoded" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "encoded" varchar(100)
);

CREATE TABLE "event" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "starts_at" date NOT NULL,
  "created_on" timestamp NOT NULL,
  "varchar_date" varchar(20),
  "varchar_datetime" varchar(20),
  "skip_inflation" datetime,
  "ts_without_tz" datetime
);

CREATE TABLE "fourkeys" (
  "foo" integer NOT NULL,
  "bar" integer NOT NULL,
  "hello" integer NOT NULL,
  "goodbye" integer NOT NULL,
  "sensors" character(10) NOT NULL,
  "read_count" int,
  PRIMARY KEY ("foo", "bar", "hello", "goodbye")
);

CREATE TABLE "genre" (
  "genreid" INTEGER PRIMARY KEY NOT NULL,
  "name" varchar(100) NOT NULL
);

CREATE UNIQUE INDEX "genre_name" ON "genre" ("name");

CREATE TABLE "link" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "url" varchar(100),
  "title" varchar(100)
);

CREATE TABLE "money_test" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "amount" money
);

CREATE TABLE "noprimarykey" (
  "foo" integer NOT NULL,
  "bar" integer NOT NULL,
  "baz" integer NOT NULL
);

CREATE UNIQUE INDEX "foo_bar" ON "noprimarykey" ("foo", "bar");

CREATE TABLE "onekey" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "artist" integer NOT NULL,
  "cd" integer NOT NULL
);

CREATE TABLE "owners" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "name" varchar(100) NOT NULL
);

CREATE UNIQUE INDEX "owners_name" ON "owners" ("name");

CREATE TABLE "producer" (
  "producerid" INTEGER PRIMARY KEY NOT NULL,
  "name" varchar(100) NOT NULL
);

CREATE UNIQUE INDEX "prod_name" ON "producer" ("name");

CREATE TABLE "self_ref" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "name" varchar(100) NOT NULL
);

CREATE TABLE "sequence_test" (
  "pkid1" integer NOT NULL,
  "pkid2" integer NOT NULL,
  "nonpkid" integer NOT NULL,
  "name" varchar(100),
  PRIMARY KEY ("pkid1", "pkid2")
);

CREATE TABLE "serialized" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "serialized" text NOT NULL
);

CREATE TABLE "timestamp_primary_key_test" (
  "id" timestamp NOT NULL DEFAULT current_timestamp,
  PRIMARY KEY ("id")
);

CREATE TABLE "treelike" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "parent" integer,
  "name" varchar(100) NOT NULL,
  FOREIGN KEY ("parent") REFERENCES "treelike"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "treelike_idx_parent" ON "treelike" ("parent");

CREATE TABLE "twokeytreelike" (
  "id1" integer NOT NULL,
  "id2" integer NOT NULL,
  "parent1" integer NOT NULL,
  "parent2" integer NOT NULL,
  "name" varchar(100) NOT NULL,
  PRIMARY KEY ("id1", "id2"),
  FOREIGN KEY ("parent1", "parent2") REFERENCES "twokeytreelike"("id1", "id2")
);

CREATE INDEX "twokeytreelike_idx_parent1_parent2" ON "twokeytreelike" ("parent1", "parent2");

CREATE UNIQUE INDEX "tktlnameunique" ON "twokeytreelike" ("name");

CREATE TABLE "typed_object" (
  "objectid" INTEGER PRIMARY KEY NOT NULL,
  "type" varchar(100) NOT NULL,
  "value" varchar(100) NOT NULL
);

CREATE TABLE "artist_undirected_map" (
  "id1" integer NOT NULL,
  "id2" integer NOT NULL,
  PRIMARY KEY ("id1", "id2"),
  FOREIGN KEY ("id1") REFERENCES "artist"("artistid") ON DELETE RESTRICT ON UPDATE CASCADE,
  FOREIGN KEY ("id2") REFERENCES "artist"("artistid")
);

CREATE INDEX "artist_undirected_map_idx_id1" ON "artist_undirected_map" ("id1");

CREATE INDEX "artist_undirected_map_idx_id2" ON "artist_undirected_map" ("id2");

CREATE TABLE "bookmark" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "link" integer,
  FOREIGN KEY ("link") REFERENCES "link"("id") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE INDEX "bookmark_idx_link" ON "bookmark" ("link");

CREATE TABLE "books" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "source" varchar(100) NOT NULL,
  "owner" integer NOT NULL,
  "title" varchar(100) NOT NULL,
  "price" integer,
  FOREIGN KEY ("owner") REFERENCES "owners"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "books_idx_owner" ON "books" ("owner");

CREATE UNIQUE INDEX "books_title" ON "books" ("title");

CREATE TABLE "employee" (
  "employee_id" INTEGER PRIMARY KEY NOT NULL,
  "position" integer NOT NULL,
  "group_id" integer,
  "group_id_2" integer,
  "group_id_3" integer,
  "name" varchar(100),
  "encoded" integer,
  FOREIGN KEY ("encoded") REFERENCES "encoded"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "employee_idx_encoded" ON "employee" ("encoded");

CREATE TABLE "forceforeign" (
  "artist" INTEGER PRIMARY KEY NOT NULL,
  "cd" integer NOT NULL,
  FOREIGN KEY ("artist") REFERENCES "artist"("artistid")
);

CREATE TABLE "self_ref_alias" (
  "self_ref" integer NOT NULL,
  "alias" integer NOT NULL,
  PRIMARY KEY ("self_ref", "alias"),
  FOREIGN KEY ("alias") REFERENCES "self_ref"("id"),
  FOREIGN KEY ("self_ref") REFERENCES "self_ref"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "self_ref_alias_idx_alias" ON "self_ref_alias" ("alias");

CREATE INDEX "self_ref_alias_idx_self_ref" ON "self_ref_alias" ("self_ref");

CREATE TABLE "track" (
  "trackid" INTEGER PRIMARY KEY NOT NULL,
  "cd" integer NOT NULL,
  "position" int NOT NULL,
  "title" varchar(100) NOT NULL,
  "last_updated_on" datetime,
  "last_updated_at" datetime,
  FOREIGN KEY ("cd") REFERENCES "cd"("cdid") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "track_idx_cd" ON "track" ("cd");

CREATE UNIQUE INDEX "track_cd_position" ON "track" ("cd", "position");

CREATE UNIQUE INDEX "track_cd_title" ON "track" ("cd", "title");

CREATE TABLE "cd" (
  "cdid" INTEGER PRIMARY KEY NOT NULL,
  "artist" integer NOT NULL,
  "title" varchar(100) NOT NULL,
  "year" varchar(100) NOT NULL,
  "genreid" integer,
  "single_track" integer,
  FOREIGN KEY ("artist") REFERENCES "artist"("artistid") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("single_track") REFERENCES "track"("trackid") ON DELETE CASCADE,
  FOREIGN KEY ("genreid") REFERENCES "genre"("genreid") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE INDEX "cd_idx_artist" ON "cd" ("artist");

CREATE INDEX "cd_idx_single_track" ON "cd" ("single_track");

CREATE INDEX "cd_idx_genreid" ON "cd" ("genreid");

CREATE UNIQUE INDEX "cd_artist_title" ON "cd" ("artist", "title");

CREATE TABLE "collection_object" (
  "collection" integer NOT NULL,
  "object" integer NOT NULL,
  PRIMARY KEY ("collection", "object"),
  FOREIGN KEY ("collection") REFERENCES "collection"("collectionid") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("object") REFERENCES "typed_object"("objectid") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "collection_object_idx_collection" ON "collection_object" ("collection");

CREATE INDEX "collection_object_idx_object" ON "collection_object" ("object");

CREATE TABLE "lyrics" (
  "lyric_id" INTEGER PRIMARY KEY NOT NULL,
  "track_id" integer NOT NULL,
  FOREIGN KEY ("track_id") REFERENCES "track"("trackid") ON DELETE CASCADE
);

CREATE INDEX "lyrics_idx_track_id" ON "lyrics" ("track_id");

CREATE TABLE "cd_artwork" (
  "cd_id" INTEGER PRIMARY KEY NOT NULL,
  FOREIGN KEY ("cd_id") REFERENCES "cd"("cdid") ON DELETE CASCADE
);

CREATE TABLE "liner_notes" (
  "liner_id" INTEGER PRIMARY KEY NOT NULL,
  "notes" varchar(100) NOT NULL,
  FOREIGN KEY ("liner_id") REFERENCES "cd"("cdid") ON DELETE CASCADE
);

CREATE TABLE "lyric_versions" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "lyric_id" integer NOT NULL,
  "text" varchar(100) NOT NULL,
  FOREIGN KEY ("lyric_id") REFERENCES "lyrics"("lyric_id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "lyric_versions_idx_lyric_id" ON "lyric_versions" ("lyric_id");

CREATE UNIQUE INDEX "lyric_versions_lyric_id_text" ON "lyric_versions" ("lyric_id", "text");

CREATE TABLE "tags" (
  "tagid" INTEGER PRIMARY KEY NOT NULL,
  "cd" integer NOT NULL,
  "tag" varchar(100) NOT NULL,
  FOREIGN KEY ("cd") REFERENCES "cd"("cdid") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "tags_idx_cd" ON "tags" ("cd");

CREATE UNIQUE INDEX "tagid_cd" ON "tags" ("tagid", "cd");

CREATE UNIQUE INDEX "tagid_cd_tag" ON "tags" ("tagid", "cd", "tag");

CREATE UNIQUE INDEX "tags_tagid_tag" ON "tags" ("tagid", "tag");

CREATE UNIQUE INDEX "tags_tagid_tag_cd" ON "tags" ("tagid", "tag", "cd");

CREATE TABLE "cd_to_producer" (
  "cd" integer NOT NULL,
  "producer" integer NOT NULL,
  "attribute" integer,
  PRIMARY KEY ("cd", "producer"),
  FOREIGN KEY ("cd") REFERENCES "cd"("cdid") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("producer") REFERENCES "producer"("producerid")
);

CREATE INDEX "cd_to_producer_idx_cd" ON "cd_to_producer" ("cd");

CREATE INDEX "cd_to_producer_idx_producer" ON "cd_to_producer" ("producer");

CREATE TABLE "images" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "artwork_id" integer NOT NULL,
  "name" varchar(100) NOT NULL,
  "data" blob,
  FOREIGN KEY ("artwork_id") REFERENCES "cd_artwork"("cd_id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "images_idx_artwork_id" ON "images" ("artwork_id");

CREATE TABLE "twokeys" (
  "artist" integer NOT NULL,
  "cd" integer NOT NULL,
  PRIMARY KEY ("artist", "cd"),
  FOREIGN KEY ("artist") REFERENCES "artist"("artistid") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("cd") REFERENCES "cd"("cdid")
);

CREATE INDEX "twokeys_idx_artist" ON "twokeys" ("artist");

CREATE TABLE "artwork_to_artist" (
  "artwork_cd_id" integer NOT NULL,
  "artist_id" integer NOT NULL,
  PRIMARY KEY ("artwork_cd_id", "artist_id"),
  FOREIGN KEY ("artist_id") REFERENCES "artist"("artistid") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("artwork_cd_id") REFERENCES "cd_artwork"("cd_id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "artwork_to_artist_idx_artist_id" ON "artwork_to_artist" ("artist_id");

CREATE INDEX "artwork_to_artist_idx_artwork_cd_id" ON "artwork_to_artist" ("artwork_cd_id");

CREATE TABLE "fourkeys_to_twokeys" (
  "f_foo" integer NOT NULL,
  "f_bar" integer NOT NULL,
  "f_hello" integer NOT NULL,
  "f_goodbye" integer NOT NULL,
  "t_artist" integer NOT NULL,
  "t_cd" integer NOT NULL,
  "autopilot" character NOT NULL,
  "pilot_sequence" integer,
  PRIMARY KEY ("f_foo", "f_bar", "f_hello", "f_goodbye", "t_artist", "t_cd"),
  FOREIGN KEY ("f_foo", "f_bar", "f_hello", "f_goodbye") REFERENCES "fourkeys"("foo", "bar", "hello", "goodbye") ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY ("t_artist", "t_cd") REFERENCES "twokeys"("artist", "cd") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "fourkeys_to_twokeys_idx_f_foo_f_bar_f_hello_f_goodbye" ON "fourkeys_to_twokeys" ("f_foo", "f_bar", "f_hello", "f_goodbye");

CREATE INDEX "fourkeys_to_twokeys_idx_t_artist_t_cd" ON "fourkeys_to_twokeys" ("t_artist", "t_cd");

CREATE VIEW "year2000cds" AS
    SELECT cdid, artist, title, year, genreid, single_track FROM cd WHERE year = "2000";
