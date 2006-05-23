package DBIx::Class::InflateColumn::DateTime;

use strict;
use warnings;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/InflateColumn/);

__PACKAGE__->mk_group_accessors('simple' => '__datetime_parser');

sub register_column {
  my ($self, $column, $info, @rest) = @_;
  $self->next::method($column, $info, @rest);
  if ($info->{data_type} =~ /^datetime$/i) {
    $self->inflate_column(
      $column =>
        {
          inflate => sub {
            my ($value, $obj) = @_;
            $obj->_datetime_parser->parse_datetime($value);
          },
          deflate => sub {
            my ($value, $obj) = @_;
            $obj->_datetime_parser->format_datetime($value);
          },
        }
    );
  }
}

sub _datetime_parser {
  my $self = shift;
  if (my $parser = $self->__datetime_parser) {
    return $parser;
  }
  my $parser = $self->result_source->storage->datetime_parser(@_);
  return $self->__datetime_parser($parser);
}

1;
