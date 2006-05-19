use Class::Inspector;

BEGIN {
  package TestPackage::A;
  sub some_method {}
}

sub run_tests {

my $schema = shift;
plan tests => 6;

ok(Class::Inspector->loaded('TestPackage::A'),
   'anon. package exists');
eval {
  $schema->ensure_class_loaded('TestPackage::A');
};

ok(!$@, 'ensure_class_loaded detected an anon. class');

eval {
  $schema->ensure_class_loaded('FakePackage::B');
};

like($@, qr/Can't locate/,
     'ensure_class_loaded threw exception for nonexistent class');

ok(!Class::Inspector->loaded('DBICTest::FakeComponent'),
   'DBICTest::FakeComponent not loaded yet');

eval {
  $schema->ensure_class_loaded('DBICTest::FakeComponent');
};

ok(!$@, 'ensure_class_loaded detected an existing but non-loaded class');
ok(Class::Inspector->loaded('DBICTest::FakeComponent'),
   'DBICTest::FakeComponent now loaded');
}

1;
