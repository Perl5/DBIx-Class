package # hide from PAUSE
    DBIx::Class::ClassResolver::PassThrough;

sub class {
  shift;
  return shift;
}

1;
