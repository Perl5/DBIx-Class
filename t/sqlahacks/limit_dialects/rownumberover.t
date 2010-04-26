use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema;

delete $schema->storage->_sql_maker->{_cached_syntax};
$schema->storage->_sql_maker->limit_dialect ('RowNumberOver');

my $rs_selectas_rno = $schema->resultset ('BooksInLibrary')->search ({}, { '+select' => ['owner.name'], '+as' => ['owner_name'], join => 'owner', rows => 1 });

is_same_sql_bind( $rs_selectas_rno->search({})->as_query,
                  "(SELECT 
                      me.id, me.source, me.owner, me.title, me.price, 
                      owner.name 
                    FROM 
                      (SELECT me.*, 
                       ROW_NUMBER() OVER( ) AS rno__row__index 
                       FROM 
                         (SELECT me.id, me.source, me.owner, me.title, me.price, owner.name 
                          FROM books me 
                          JOIN owners owner ON owner.id = me.owner 
                          WHERE ( source = ? ) 
                         ) me 
                       ) me 
                    JOIN owners owner ON owner.id = me.owner
                    WHERE rno__row__index BETWEEN 1 AND 1 )",
                  [  [ 'source', 'Library' ] ],
                );


done_testing;
