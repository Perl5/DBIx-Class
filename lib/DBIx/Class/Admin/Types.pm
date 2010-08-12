package # hide from PAUSE
    DBIx::Class::Admin::Types;

use MooseX::Types -declare => [qw(
    DBICConnectInfo
    DBICArrayRef
    DBICHashRef
    DiffSource
)];
use MooseX::Types::Moose ':all';
use MooseX::Types::JSON qw(JSON);
use DBIx::Class::Admin::Diff::Source;

subtype DBICArrayRef,
    as ArrayRef;

coerce DBICArrayRef,
  from JSON,
  via { _json_to_data ($_) };

subtype DBICHashRef,
    as HashRef;

coerce DBICHashRef,
  from JSON,
  via { _json_to_data($_) };

subtype DBICConnectInfo,
  as ArrayRef;

coerce DBICConnectInfo,
  from JSON,
   via { return _json_to_data($_) },
  from Str,
    via { return _json_to_data($_) },
  from HashRef,
   via { [ $_ ] }
  ;

subtype DiffSource,
    as Object,
      where { blessed $_ and $_->isa('DBIx::Class::Admin::Diff::Source') };

coerce DiffSource,
  from Str, via { _str_diff_source($_) },
  from ArrayRef, via { _array_diff_source($_) },
  from HashRef, via { _hash_diff_source($_) },
  from Object, via { _object_diff_source($_) }
  ;

sub _json_to_data {
  my ($json_str) = @_;
  my $json = JSON::Any->new(allow_barekey => 1, allow_singlequote => 1, relaxed=>1);
  my $ret = $json->jsonToObj($json_str);
  return $ret;
}

sub _str_diff_source {
  my $str = $_;
  my $input = _json_to_data($str);

  return ref $input eq 'ARRAY' ? _array_diff_source($input)
       : ref $input eq 'HASH'  ? _hash_diff_source($input)
       :                         $str;
}

sub _array_diff_source {
  my $args = $_;
  my $class = _generate_classname();

  DBIx::Class::Schema::Loader::make_schema_at($class,
    { naming => 'v7', preserve_case => 1 },
    $args,
  );

  return DBIx::Class::Admin::Diff::Source->new(class => $class);
}

sub _hash_diff_source {
  return DBIx::Class::Admin::Diff::Source->new($_);
}

sub _object_diff_source {
  my $dbh = $_;
  my $class = _generate_classname();

  unless(blessed $dbh eq 'DBI::db') {
    return $dbh;
  }

  DBIx::Class::Schema::Loader::make_schema_at($class,
    { naming => 'v7', preserve_case => 1 },
    [ sub { $dbh } ],
  );

  return DBIx::Class::Admin::Diff::Source->new(class => $class);
}

{
  my $generated = 0;
  sub _generate_classname {
    __PACKAGE__ .'::GEN' .(++$generated) .'::Schema'
  }
}

1;
