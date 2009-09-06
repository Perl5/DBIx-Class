#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBICTest::Schema;

{
  package Dying::Storage;

  use warnings;
  use strict;

  use base 'DBIx::Class::Storage::DBI';

  sub _populate_dbh {
    my $self = shift;
    my $death = $self->_dbi_connect_info->[3]{die};

    die "storage test died: $death" if $death eq 'before_populate';
    my $ret = $self->next::method (@_);
    die "storage test died: $death" if $death eq 'after_populate';

    return $ret;
  }
}

TODO: {
local $TODO = "I have no idea what is going on here... but it ain't right";

for (qw/before_populate after_populate/) {

  dies_ok (sub {
    my $schema = DBICTest::Schema->clone;
    $schema->storage_type ('Dying::Storage');
    $schema->connection (DBICTest->_database, { die => $_ });
    $schema->storage->ensure_connected;
  }, "$_ exception found");
}

}

done_testing;

__END__
For reference - next::method goes to ::Storage::DBI::_populate_dbh
which is:

sub _populate_dbh {
  my ($self) = @_;

  my @info = @{$self->_dbi_connect_info || []};
  $self->_dbh(undef); # in case ->connected failed we might get sent here 
  $self->_dbh($self->_connect(@info));

  $self->_conn_pid($$);
  $self->_conn_tid(threads->tid) if $INC{'threads.pm'};

  $self->_determine_driver;

  # Always set the transaction depth on connect, since 
  #  there is no transaction in progress by definition 
  $self->{transaction_depth} = $self->_dbh_autocommit ? 0 : 1;

  $self->_run_connection_actions unless $self->{_in_determine_driver};
}

After further tracing it seems that if I die() before $self->_conn_pid($$)
the exception is propagated. If I die after it - it's lost. What The Fuck?!
