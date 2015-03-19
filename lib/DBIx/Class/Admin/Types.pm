package # hide from PAUSE
    DBIx::Class::Admin::Types;

use warnings;
use strict;

use Type::Library
  -base,
  -declare => qw(
    Dir File
    DBICConnectInfo
    DBICArrayRef
    DBICHashRef
);
use Type::Utils -all;
use Types::Standard qw/HashRef ArrayRef Str/;
use Path::Class;

class_type Dir, { class => 'Path::Class::Dir' };
class_type File, { class => 'Path::Class::File' };

coerce Dir, from Str, via { dir($_) };
coerce File, from Str, via { file($_) };

subtype DBICArrayRef,
    as ArrayRef;

subtype DBICHashRef,
    as HashRef;

coerce DBICArrayRef,
  from Str,
  via { _json_to_data ($_) };

coerce DBICHashRef,
  from Str,
  via { _json_to_data($_) };

subtype DBICConnectInfo,
  as ArrayRef;

coerce DBICConnectInfo,
  from Str, via { _json_to_data($_) },
  from HashRef, via { [ $_ ] };

sub _json_to_data {
  my ($json_str) = @_;
  require JSON::Any;
  my $json = JSON::Any->new(allow_barekey => 1, allow_singlequote => 1, relaxed=>1);
  my $ret = $json->jsonToObj($json_str);
  return $ret;
}

1;
