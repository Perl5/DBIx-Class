package DBIx::Class::ClassResolver::PassThrough;

sub class {
  shift;
  return shift;
}

1;
