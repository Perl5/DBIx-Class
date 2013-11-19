package DBIx::Class::ResultSet::WithDQMethods;

use Scalar::Util qw(blessed);
use Moo;
use Moo::Object;
use namespace::clean;

extends 'DBIx::Class::ResultSet';

with 'DBIx::Class::ResultSet::Role::DQMethods';

sub BUILDARGS {
  if (@_ <= 3 and blessed($_[1])) { # ->new($source, $attrs?)
    return $_[2]||{};
  }
  return Moo::Object::BUILDARGS(@_);
}

sub FOREIGNBUILDARGS {
  if (@_ <= 3 and blessed($_[1])) { # ->new($source, $attrs?)
    return ($_[1], $_[2]);
  }
  my $args = Moo::Object::BUILDARGS(@_);
  my $source = delete $args->{result_source};
  return ($source, $args);
}

1;
