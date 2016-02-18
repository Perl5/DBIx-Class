use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

plan tests => 4;

my $schema = DBICTest->init_schema();

lives_ok ( sub {

  my $artist_rs =  $schema->resultset ('Artist');
  my $artist_count =  $artist_rs->count();
  my $cd_rs    =  $schema->resultset ('CD');
  my $cd_count =  $cd_rs->count();
  $artist_rs->create({
    name => 'parent child relation',
    cds => [ {}, {} ], #CD's 'title' field are autofilled at CD::new
  });

  is ($artist_rs->count, $artist_count + 1, 'New artist was created');
  ok ($artist_rs->find ({name => 'parent child relation'}), 'Artist was created with correct name');

  is ($cd_rs->count, $cd_count + 2, 'New cds were created');
  is ($cd_rs->search({name => 'parent child relation'})->count, 2, 'CDs were created with correct name');

}, 'Parent row must exist before child row is created');

1;

package # hide from PAUSE
  DBICTest::Schema::CD;

sub new {
  my ( $class, $attrs ) = @_;

my $self = $class->next::method($attrs);

$self->title( $self->artist->name );

return $self;
}


1;
