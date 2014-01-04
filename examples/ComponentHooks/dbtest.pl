#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin . '/lib';

use DB;
use Test::More;

# Connection
my $s = DB->connect('dbi:SQLite:db/db.db');

# Clear DB
$s->resultset('Realty::House::Sell')->delete;
$s->resultset('Realty::House::Rent')->delete;
$s->resultset('Realty::Apartment::Sell')->delete;
$s->resultset('Realty::Apartment::Rent')->delete;
$s->resultset('Realty::Apartment::Rent::Daily')->delete;


# House Sell
my $house_sell_data = {
    id              => 1,
    address         => '600011, AD, Dres, s 5',
    house_square    => 260,
    floors          => 2,
    price_per_meter => 1000,
};

ok(
    my $house = $s->resultset('Realty::House::Sell')->create($house_sell_data),
    'Realty::House::Sell Added'
);

$house = $house->get_from_storage(
    {
        result_class => 'DBIx::Class::ResultClass::HashRefInflator'
    }
);

is_deeply( $house, $house_sell_data, 'Realty::House::Sell retrieved' );


# House Rent
my $house_rent_data = {
    id              => 2,
    address         => '600012, AD, Dres, s 5',
    house_square    => 260,
    floors          => 2,
    min_rent_period => 12,
    price_per_month => 800,
};

ok( $house = $s->resultset('Realty::House::Rent')->create($house_rent_data),
    'Realty::House::Rent Added' );

$house = $house->get_from_storage(
    {
        result_class => 'DBIx::Class::ResultClass::HashRefInflator'
    }
);

is_deeply( $house, $house_rent_data, 'Realty::House::Rent retrieved' );


# Apartment Sell
my $apartment_sell_data = {
    id              => 3,
    address         => '600013, AD, Dres, s 5, app. 255',
    square          => 50,
    rooms           => 1,
    floor           => 15,
    price_per_meter => 900,
};

ok(
    my $apartment
        = $s->resultset('Realty::Apartment::Sell')
        ->create($apartment_sell_data),
    'Realty::Apartment::Sell Added'
);

$apartment = $apartment->get_from_storage(
    {
        result_class => 'DBIx::Class::ResultClass::HashRefInflator'
    }
);

is_deeply( $apartment, $apartment_sell_data,
    'Realty::Apartment::Sell retrieved' );


# Apartment Rent
my $apartment_rent_data = {
    id              => 4,
    address         => '600013, AD, Dres, s 6, app. 255',
    square          => 50,
    rooms           => 1,
    floor           => 15,
    min_rent_period => 12,
    price_per_month => 500,
};

ok(
    $apartment
        = $s->resultset('Realty::Apartment::Rent')
        ->create($apartment_rent_data),
    'Realty::Apartment::Rent Added'
);

$apartment = $apartment->get_from_storage(
    {
        result_class => 'DBIx::Class::ResultClass::HashRefInflator'
    }
);

is_deeply( $apartment, $apartment_rent_data,
    'Realty::Apartment::Rent retrieved' );

# Apartment Rent Daily
my $apartment_rent_daily_data = {
    id              => 4,
    address         => '600013, AD, Dres, s 6, app. 255',
    square          => 50,
    rooms           => 1,
    floor           => 15,
    min_rent_period => 12,
    price_per_day   => 500,
    checkout_time   => '10:00',
};

ok(
    $apartment
        = $s->resultset('Realty::Apartment::Rent::Daily')
        ->create($apartment_rent_daily_data),
    'Realty::Apartment::Rent::Daily Added'
);

$apartment = $apartment->get_from_storage(
    {
        result_class => 'DBIx::Class::ResultClass::HashRefInflator'
    }
);

is_deeply( $apartment, $apartment_rent_daily_data,
    'Realty::Apartment::Rent::Daily retrieved' );

done_testing();
