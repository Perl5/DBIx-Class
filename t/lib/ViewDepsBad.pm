package    # hide from PAUSE
    ViewDepsBad;
## Used in 105view_deps.t

use strict;
use warnings;
use base 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces;

sub sqlt_deploy_hook {
    my $self = shift;
    $self->{sqlt} = shift;
}

1;
