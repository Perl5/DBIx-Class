CREATE TABLE house_rent (
    id                INTEGER NOT NULL PRIMARY KEY,
    address           TEXT    NOT NULL,

    min_rent_period   INT     NOT NULL,
    price_per_month   FLOAT   NOT NULL,

    house_square      FLOAT   NOT NULL,
    floors            INT     NOT NULL
);

CREATE TABLE house_sell (
    id                INTEGER NOT NULL PRIMARY KEY,
    address           TEXT    NOT NULL,

    price_per_meter   FLOAT   NOT NULL,

    house_square      FLOAT   NOT NULL,
    floors            INT     NOT NULL
);

CREATE TABLE apartment_rent (
    id                INTEGER NOT NULL PRIMARY KEY,
    address           TEXT    NOT NULL,

    min_rent_period   INT     NOT NULL,
    price_per_month   FLOAT   NOT NULL,

    square            FLOAT   NOT NULL,
    rooms             INT     NOT NULL,
    floor             INT     NOT NULL
);

CREATE TABLE apartment_rent_daily (
    id                INTEGER NOT NULL PRIMARY KEY,
    address           TEXT    NOT NULL,

    min_rent_period   INT     NOT NULL,
    price_per_day     FLOAT   NOT NULL,
    checkout_time     TIME    NOT NULL,

    square            FLOAT   NOT NULL,
    rooms             INT     NOT NULL,
    floor             INT     NOT NULL
);

CREATE TABLE apartment_sell (
    id                INTEGER NOT NULL PRIMARY KEY,
    address           TEXT    NOT NULL,

    price_per_meter   FLOAT   NOT NULL,

    square            FLOAT   NOT NULL,
    rooms             INT     NOT NULL,
    floor             INT     NOT NULL
);
