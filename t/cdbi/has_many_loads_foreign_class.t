BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => 'cdbicompat';

use strict;
use warnings;

use Test::More;

use lib 't/cdbi/testlib';
use DBICTest::Util 'class_seems_loaded';
use Director;

# Test that has_many() will load the foreign class
ok ! class_seems_loaded('Film'), 'Start non-loaded';
ok eval { Director->has_many( films => 'Film' ); 1; } or diag $@;

my $shan_hua = Director->create({
    Name    => "Shan Hua",
});

my $inframan = Film->create({
    Title       => "Inframan",
    Director    => "Shan Hua",
});
my $guillotine2 = Film->create({
    Title       => "Flying Guillotine 2",
    Director    => "Shan Hua",
});
my $guillotine = Film->create({
    Title       => "Master of the Flying Guillotine",
    Director    => "Yu Wang",
});

is_deeply [sort $shan_hua->films], [sort $inframan, $guillotine2];

done_testing;
