use Storable;

sub run_tests {
my $schema = shift;

plan tests => 1;

my $artist = $schema->resultset('Artist')->find(1);
my $copy = eval { Storable::dclone($artist) };
is_deeply($copy, $artist, 'serialize row object works');

}

1;
