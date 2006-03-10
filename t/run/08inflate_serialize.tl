sub run_tests {
my $schema = shift;

use Data::Dumper;

my @serializers = (
    {	module => 'YAML.pm',
	inflater => sub { YAML::Load (shift) },
	deflater => sub { die "Expecting a reference" unless (ref $_[0]); YAML::Dump (shift) },
    },
    {	module => 'Storable.pm',
	inflater => sub { Storable::thaw (shift) },
	deflater => sub { die "Expecting a reference" unless (ref $_[0]); Storable::nfreeze (shift) },
    },
);


my $selected;
foreach my $serializer (@serializers) {
    eval { require $serializer->{module} };
    unless ($@) {
	$selected = $serializer;
	last;
    }
}

plan (skip_all => "No suitable serializer found") unless $selected;

plan (tests => 6);
DBICTest::Schema::Serialized->inflate_column( 'serialized',
    { inflate => $selected->{inflater},
      deflate => $selected->{deflater},
    },
);
Class::C3->reinitialize;

my $complex1 = {
    id => 1,
    serialized => {
        a => 1,
	b => [ 
	    { c => 2 },
	],
        d => 3,
    },
};

my $complex2 = {
    id => 1,
    serialized => [
		'a', 
		{ b => 1, c => 2},
		'd',
	    ],
};

my $rs = $schema->resultset('Serialized');
my $entry = $rs->create({ id => 1, serialized => ''});

my $inflated;

ok($entry->update ({ %{$complex1} }), 'hashref deflation ok');
ok($inflated = $entry->serialized, 'hashref inflation ok');
is_deeply($inflated, $complex1->{serialized}, 'inflated hash matches original');

ok($entry->update ({ %{$complex2} }), 'arrayref deflation ok');
ok($inflated = $entry->serialized, 'arrayref inflation ok');
is_deeply($inflated, $complex2->{serialized}, 'inflated array matches original');

}

1;
