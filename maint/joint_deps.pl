#!/usr/bin/perl

use warnings;
use strict;

use CPANDB;
use DBIx::Class::Schema::Loader 0.05;
use Data::Dumper::Concise;

{
  package CPANDB::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options (
    naming => 'v5',
  );
}

my $s = CPANDB::Schema->connect (sub { CPANDB->dbh } );

# reference names are unstable - just create rels manually
# is there a saner way to do that?
my $distclass = $s->class('Distribution');
$distclass->has_many (
  'deps',
  $s->class('Dependency'),
  'distribution',
);
$s->unregister_source ('Distribution');
$s->register_class ('Distribution', $distclass);


# a proof of concept how to find out who uses us *AND* SQLT
my $us_and_sqlt = $s->resultset('Distribution')->search (
  {
    'deps.dependency' => 'DBIx-Class',
    'deps_2.dependency' => 'SQL-Translator',
  },
  {
    join => [qw/deps deps/],
    order_by => 'me.author',
    select => [ 'me.distribution', 'me.author', map { "$_.phase" } (qw/deps deps_2/)],
    as => [qw/dist_name dist_author req_dbic_at req_sqlt_at/],
    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
  },
);

print Dumper [$us_and_sqlt->all];
