#   belongs to t/05components.t
package DBICTest::ForeignComponent;
use warnings;
use strict;

use base qw/ DBIx::Class /;

__PACKAGE__->load_components( qw/ +DBICTest::ForeignComponent::TestComp / );

1;
