use warnings;
use strict;

use Test::More;

use lib qw(t/lib);
use DBICTest;

package My::Schema::Result::User;

use strict;
use warnings;
use base qw/DBIx::Class::Core/;

### Define what our admin class is, for ensure_class_loaded()
my $admin_class = __PACKAGE__ . '::Admin';

__PACKAGE__->table('users');

__PACKAGE__->add_columns(
    qw/user_id   email    password
      firstname lastname active
      admin/
);

__PACKAGE__->set_primary_key('user_id');

sub inflate_result {
    my $self = shift;
    my $ret  = $self->next::method(@_);
    if ( $ret->admin ) {    ### If this is an admin, rebless for extra functions
        $self->ensure_class_loaded($admin_class);
        bless $ret, $admin_class;
    }
    return $ret;
}

sub hello {
    return "I am a regular user.";
}

package My::Schema::Result::User::Admin;

use strict;
use warnings;
use base qw/My::Schema::Result::User/;

# This line is important
__PACKAGE__->table('users');

sub hello {
    return "I am an admin.";
}

sub do_admin_stuff {
    return "I am doing admin stuff";
}

package My::Schema;

use base qw/DBIx::Class::Schema/;

My::Schema->register_class( Admin => 'My::Schema::Result::User::Admin' );
My::Schema->register_class( User  => 'My::Schema::Result::User' );

1;

package main;
my $user_data = {
    email    => 'someguy@place.com',
    password => 'pass1',
    admin    => 0
};

my $admin_data = {
    email    => 'someadmin@adminplace.com',
    password => 'pass2',
    admin    => 1
};

ok( my $schema = My::Schema->connection(DBICTest->_database) );

ok(
    $schema->storage->dbh->do(
"create table users (user_id, email, password, firstname, lastname, active,  admin)"
    )
);

TODO: {
    local $TODO = 'New objects should also be inflated';
    my $user  = $schema->resultset('User')->create($user_data);
    my $admin = $schema->resultset('User')->create($admin_data);

    is( ref $user,  'My::Schema::Result::User' );
    is( ref $admin, 'My::Schema::Result::User::Admin' );
}

my $user  = $schema->resultset('User')->single($user_data);
my $admin = $schema->resultset('User')->single($admin_data);

is( ref $user,  'My::Schema::Result::User' );
is( ref $admin, 'My::Schema::Result::User::Admin' );

is( $user->password,  'pass1' );
is( $admin->password, 'pass2' );
is( $user->hello,     'I am a regular user.' );
is( $admin->hello,    'I am an admin.' );

ok( !$user->can('do_admin_stuff') );
ok( $admin->can('do_admin_stuff') );

done_testing;
