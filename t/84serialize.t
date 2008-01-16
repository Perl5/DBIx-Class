use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;
use Storable qw(dclone freeze thaw);

my $schema = DBICTest->init_schema();

my %stores = (
    dclone          => sub { return dclone($_[0]) },
    "freeze/thaw"   => sub { return thaw(freeze($_[0])) },
);

plan tests => (7 * keys %stores);

for my $name (keys %stores) {
    my $store = $stores{$name};

    my $artist = $schema->resultset('Artist')->find(1);
    my $copy = eval { $store->($artist) };
    is_deeply($copy, $artist, "serialize row object works: $name");

    # Test that an object with a related_resultset can be serialized.
    my @cds = $artist->related_resultset("cds");
    ok $artist->{related_resultsets}, 'has key: related_resultsets';

    $copy = eval { $store->($artist) };
    for my $key (keys %$artist) {
        next if $key eq 'related_resultsets';
        next if $key eq '_inflated_column';
        is_deeply($copy->{$key}, $artist->{$key},
                  qq[serialize with related_resultset "$key"]);
    }
  
    ok eval { $copy->discard_changes; 1 };
    is($copy->id, $artist->id, "IDs still match ");
}
