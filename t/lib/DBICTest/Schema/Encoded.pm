package # hide from PAUSE
    DBICTest::Schema::Encoded;

use strict;
use warnings;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table('encoded');
__PACKAGE__->add_columns(
    'id' => {
        data_type => 'integer',
        is_auto_increment => 1
    },
    'encoded' => {
        data_type => 'varchar',
        size      => 100,
        is_nullable => 1,
    },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many (keyholders => 'DBICTest::Schema::Employee', 'encoded');

sub set_column {
  my ($self, $col, $value) = @_;
  if( $col eq 'encoded' ){
    $value = reverse split '', $value;
  }
  $self->next::method($col, $value);
}

sub new {
  my($self, $attr, @rest) = @_;
  $attr->{encoded} = reverse split '', $attr->{encoded}
    if defined $attr->{encoded};
  return $self->next::method($attr, @rest);
}

1;
