use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

{
    package DBICTest::ExplodingStorage::Sth;
    use strict;
    use warnings;

    sub execute { die "Kablammo!" }

    sub bind_param {}

    package DBICTest::ExplodingStorage;
    use strict;
    use warnings;
    use base 'DBIx::Class::Storage::DBI::SQLite';

    my $count = 0;
    sub sth {
      my ($self, $sql) = @_;
      return bless {},  "DBICTest::ExplodingStorage::Sth" unless $count++;
      return $self->next::method($sql);
    }

    sub connected {
      return 0 if $count == 1;
      return shift->next::method(@_);
    }
}

plan tests => 3;

my $schema = DBICTest->init_schema();

is( ref($schema->storage), 'DBIx::Class::Storage::DBI::SQLite',
    'Storage reblessed correctly into DBIx::Class::Storage::DBI::SQLite' );


my $storage = $schema->storage;
$storage->ensure_connected;

bless $storage, "DBICTest::ExplodingStorage";
$schema->storage($storage);

eval { 
    $schema->resultset('Artist')->create({ name => "Exploding Sheep" }) 
};

is($@, "", "Exploding \$sth->execute was caught");

is(1, $schema->resultset('Artist')->search({name => "Exploding Sheep" })->count,
  "And the STH was retired");


1;
