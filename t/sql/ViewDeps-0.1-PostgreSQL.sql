-- 
-- Created by SQL::Translator::Producer::PostgreSQL
-- Created on Fri May 28 08:01:56 2010
-- 
--
-- Table: just_a_table
--
DROP TABLE "just_a_table" CASCADE;
CREATE TABLE "just_a_table" (
  "id" serial NOT NULL,
  "name" character varying(255) NOT NULL,
  PRIMARY KEY ("id")
);

--
-- Table: mixin
--
DROP TABLE "mixin" CASCADE;
CREATE TABLE "mixin" (
  "id" serial NOT NULL,
  "words" text NOT NULL,
  PRIMARY KEY ("id")
);

--
-- Table: baz
--
DROP TABLE "baz" CASCADE;
CREATE TABLE "baz" (
  "id" integer NOT NULL
);
CREATE INDEX "baz_idx_b" on "baz" ("b");

--
-- View: "bar"
--
DROP VIEW "bar";
CREATE VIEW "bar" ( "id", "a", "b" ) AS
    select * from just_a_table
;

--
-- View: "foo"
--
DROP VIEW "foo";
CREATE VIEW "foo" ( "id", "a" ) AS
    select * from just_a_table
;

--
-- Foreign Key Definitions
--

ALTER TABLE "baz" ADD FOREIGN KEY ("b")
  REFERENCES "just_a_table" ("id") DEFERRABLE;

