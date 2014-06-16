use strict;
use warnings;
use Test::More;

use lib 't/cdbi/testlib';
use Film;
use Order;

Film->has_many(orders => 'Order');
Order->has_a(film => 'Film');

Film->create_test_film;

my $film = Film->retrieve('Bad Taste');
isa_ok $film => 'Film';

$film->add_to_orders({ orders => 10 });

my $bto = (Order->search(film => 'Bad Taste'))[0];
isa_ok $bto => 'Order';
is $bto->orders, 10, "Correct number of orders";


my $infilm = $bto->film;
isa_ok $infilm, "Film";

is $infilm->id, $film->id, "Orders hasa Film";

done_testing;
