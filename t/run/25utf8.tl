sub run_tests {
    my $schema = shift;

    eval 'use Encode ; 1'
        or plan skip_all, 'Install Encode run this test';

    plan tests => 2;

    DBICTest::Schema::Artist->load_components('UTF8Columns');
    DBICTest::Schema::Artist->utf8_columns('name');
    Class::C3->reinitialize();

    my $artist = $schema->resultset("Artist")->create( { name => 'uni' } );
    ok( Encode::is_utf8( $artist->name ), 'got name with utf8 flag' );

    my $utf8_char = 'uniuni';
    Encode::_utf8_on($utf8_char);
    $artist->name($utf8_char);
    ok( !Encode::is_utf8( $artist->{_column_data}->{name} ),
        'store utf8 less chars' );
}

1;
