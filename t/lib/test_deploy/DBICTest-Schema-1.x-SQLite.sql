--
-- This table line should not be skipped
--
CREATE TABLE artist (
  artistid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100),
  rank integer NOT NULL DEFAULT 13,
  charfield char(10)
);

CREATE INDEX artist_name_hookidx ON artist (name); -- This line should error if artist was not parsed correctly
