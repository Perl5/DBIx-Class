#!/usr/bin/perl

use strict;
use warnings;
use lib qw(lib t/lib);

use UNIVERSAL::require;

my $from = 'SQL::Translator::Parser::DBIx::Class';
my $to = 'SQL::Translator::Producer::SQLite';
my $sqlt = 'SQL::Translator';
my $schema = 'DBICTest::Schema';

$from->require;
$to->require;
$sqlt->require;
$schema->require;

my $tr = $sqlt->new;

$from->can("parse")->($tr, $schema);
print $to->can("produce")->($tr);
