#!/usr/bin/perl -w

use strict;
use Test::More tests => 12;
use Test::Warn;

package Temp::DBI;
use base qw(DBIx::Class::CDBICompat);
Temp::DBI->columns(All => qw(id date));
Temp::DBI->has_a( date => 'Time::Piece', inflate => sub { 
	Time::Piece->strptime(shift, "%Y-%m-%d") 
});


package Temp::Person;
use base 'Temp::DBI';
Temp::Person->table('people');
Temp::Person->columns(Info => qw(name pet));
Temp::Person->has_a( pet => 'Temp::Pet' );

package Temp::Pet;
use base 'Temp::DBI';
Temp::Pet->table('pets');
Temp::Pet->columns(Info => qw(name));
Temp::Pet->has_many(owners => 'Temp::Person');

package main;

{
    my $pn_meta = Temp::Person->meta_info('has_a');
    is_deeply [sort keys %$pn_meta], [qw/date pet/], "Person has Date and Pet";
}

{
    my $pt_meta = Temp::Pet->meta_info;
    is_deeply [keys %{$pt_meta->{has_a}}], [qw/date/], "Pet has Date";
    is_deeply [keys %{$pt_meta->{has_many}}], [qw/owners/], "And owners";
}

{
    my $pet = Temp::Person->meta_info( has_a => 'pet' );
    is $pet->class,         'Temp::Person';
    is $pet->foreign_class, 'Temp::Pet';
    is $pet->accessor,      'pet';
    is $pet->name,          'has_a';
}

{
    my $owners = Temp::Pet->meta_info( has_many => 'owners' );
    warning_like {
        local $TODO = 'args is unlikely to ever work';

        is_deeply $owners->args, {
            foreign_key     => 'pet',
            mapping         => [],
            order_by        => undef
        };
    } qr/^\Qargs() is unlikely to ever work/;
}

{
    my $date = Temp::Pet->meta_info( has_a => 'date' );
    is $date->class,            'Temp::DBI';
    is $date->foreign_class,    'Time::Piece';
    is $date->accessor,         'date';
}
