#   belongs to t/86sqlt.t
package # hide from PAUSE
    DBICTest::DeployComponent;
use warnings;
use strict;

our $hook_cb;

sub sqlt_deploy_hook {
  my $class = shift;

  $hook_cb->($class, @_) if $hook_cb;
  $class->next::method(@_) if $class->next::can;
}

1;
