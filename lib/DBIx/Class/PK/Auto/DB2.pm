package DBIx::Class::PK::Auto::DB2;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto/);

sub last_insert_id
{
    my ($self) = @_;

    my $dbh = $self->storage->dbh;
    my $sth = $dbh->prepare_cached("VALUES(IDENTITY_VAL_LOCAL())");
    $sth->execute();

    my @res = $sth->fetchrow_array();

    return @res ? $res[0] : undef;
                         
}

1;
