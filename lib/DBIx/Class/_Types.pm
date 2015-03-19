package # hide from PAUSE
  DBIx::Class::_Types;

use strict;
use warnings;
use Carp qw(confess);

use Path::Class;
use Sub::Name;
use Scalar::Util qw(blessed looks_like_number reftype);
use Class::Load qw(load_optional_class);

sub import {
  my ($package, @methods) = @_;
  my $caller = caller;
  for my $method (@methods) {
    my $check = $package->can($method) or confess "$package does not export $method";
    my $coerce = $package->can("coerce_$method");
    my $full_method = "${caller}::${method}";
    { no strict;
      *{$full_method} = subname $full_method => sub {
        my %args = @_;
        ($coerce && $args{coerce} && wantarray)
          ? ( $check, coerce => $coerce )
          : $check;
      };
    }
  }
}

sub error {
  my ($default, $value, %args) = @_;
  if(my $err = $args{err}) {
    confess $err->($value);
  } else {
    confess $default;
  }
}

sub Str {
  error("Value $_[0] must be a string")
    unless Defined(@_) && !ref $_[0];
}

sub Dir {
  error("Value $_[0] must be a Path::Class::Dir")
    unless Object(@_) && $_[0]->isa("Path::Class::Dir");
}

sub coerce_Dir{ dir($_[0]) }

sub File {
  error("Value $_[0] must be a Path::Class::File")
    unless Object(@_) && $_[0]->isa("Path::Class::File");
}

sub coerce_File { file($_[0]) }

sub Defined {
  error("Value must be Defined", @_)
    unless defined($_[0]);
}

sub UnDefined {
  error("Value must be UnDefined", @_)
    unless !defined($_[0]);
}

sub Bool {
  error("$_[0] is not a valid Boolean", @_)
    unless(!defined($_[0]) || $_[0] eq "" || "$_[0]" eq '1' || "$_[0]" eq '0');
}

sub Number {
  error("weight must be a Number greater than or equal to 0, not $_[0]", @_)
    unless(Defined(@_) && looks_like_number($_[0]));
}

sub Integer {
  error("$_[0] must be an Integer", @_)
    unless(Number(@_) && (int($_[0]) == $_[0]));
}

sub HashRef {
  error("$_[0] must be a HashRef", @_)
    unless(Defined(@_) && (reftype($_[0]) eq 'HASH'));
}

sub ArrayRef {
  error("$_[0] must be an ArrayRef", @_)
    unless(Defined(@_) && (reftype($_[0]) eq 'ARRAY'));
}

sub _json_to_data {
  my ($json_str) = @_;
  require JSON::Any;
  JSON::Any->import(qw(DWIW XS JSON));
  my $json = JSON::Any->new(allow_barekey => 1, allow_singlequote => 1, relaxed=>1);
  my $ret = $json->jsonToObj($json_str);
  return $ret;
}

sub DBICHashRef {
  HashRef(@_);
}

sub coerce_DBICHashRef {
  !ref $_[0] ? _json_to_data(@_)
    : reftype $_[0] eq 'HASH' ? $_[0]
    : error("Cannot coerce @{[reftype $_[0]]}")
  ;
}

sub DBICConnectInfo {
  ArrayRef(@_);
}

sub coerce_DBICConnectInfo {
  !ref $_[0] ? _json_to_data(@_)
    : reftype $_[0] eq 'ARRAY' ? $_[0]
    : reftype $_[0] eq 'HASH'  ? [ $_[0] ]
    : error("Cannot coerce @{[reftype $_[0]]}")
  ;
}

sub PositiveNumber {
  error("value must be a Number greater than or equal to 0, not $_[0]", @_)
    unless(Number(@_) && ($_[0] >= 0));
}

sub PositiveInteger {
  error("Value must be a Number greater than or equal to 0, not $_[0]", @_)
    unless(Integer(@_) && ($_[0] >= 0));
}

sub LoadableClass {
  error("$_[0] is not a loadable Class", @_)
    unless(load_optional_class($_[0]));
}

sub Object {
  error("Value is not an Object", @_)
    unless(Defined(@_) && blessed($_[0]));
}

sub DBICStorageDBI {
  error("Need an Object of type DBIx::Class::Storage::DBI, not ".ref($_[0]), @_)
    unless(Object(@_) && ($_[0]->isa('DBIx::Class::Storage::DBI')));
}

sub DBICStorageDBIReplicatedPool {
  error("Need an Object of type DBIx::Class::Storage::DBI::Replicated::Pool, not ".ref($_[0]), @_)
    unless(Object(@_) && ($_[0]->isa('DBIx::Class::Storage::DBI::Replicated::Pool')));
}

sub DBICSchema {
  error("Need an Object of type DBIx::Class::Schema, not ".ref($_[0]), @_)
    unless(Object(@_) && ($_[0]->isa('DBIx::Class::Schema')));
}

sub DBICSchemaClass {
  error("Need an Object of type DBIx::Class::Schema, not ".ref($_[0]), @_)
    unless(LoadableClass(@_) && ($_[0]->isa('DBIx::Class::Schema')));
}

sub DoesDBICStorageReplicatedBalancer {
  error("$_[0] does not do DBIx::Class::Storage::DBI::Replicated::Balancer", @_)
    unless(Object(@_) && $_[0]->does('DBIx::Class::Storage::DBI::Replicated::Balancer') );
}

1;

