use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;

# Set up the "usual" sqlite for DBICTest
my $schema = DBICTest->init_schema;

# This is how we're generating exceptions in the rest of these tests,
#  which might need updating at some future time to be some other
#  exception-generating statement:

my $throw  = sub { $schema->resultset("Artist")->search(1,1,1) };
my $ex_regex = qr/Odd number of arguments to search/;

# Basic check, normal exception
throws_ok \&$throw, $ex_regex;

my $e = $@;

# Re-throw the exception with rethrow()
throws_ok { $e->rethrow }
  $ex_regex;
isa_ok( $@, 'DBIx::Class::Exception' );

# Now lets rethrow via exception_action
{
  my $handler_execution_counter = 0;

  $schema->exception_action(sub {
    $handler_execution_counter++;
    like $_[0], $ex_regex, "Exception is precisely passed to exception_action";
    die @_
  });

  throws_ok \&$throw, $ex_regex;
  is $handler_execution_counter, 1, "exception_action handler executed exactly once";
}

#
# This should have never worked!!!
#
# Now lets suppress the error
$schema->exception_action(sub { 1 });
throws_ok \&$throw,
  qr/exception_action handler .+ did \*not\* result in an exception.+original error: $ex_regex/;

# Now lets fall through and let croak take back over
$schema->exception_action(sub { return });
throws_ok {
  warnings_are \&$throw,
    qr/exception_action handler installed .+ returned false instead throwing an exception/;
} $ex_regex;

# again to see if no warning
throws_ok {
  warnings_are \&$throw,
    [];
} $ex_regex;


# Whacky useless exception class
{
    package DBICTest::Exception;
    use overload '""' => \&stringify, fallback => 1;
    sub new {
        my $class = shift;
        bless { msg => shift }, $class;
    }
    sub throw {
        my $self = shift;
        die $self if ref $self eq __PACKAGE__;
        die $self->new(shift);
    }
    sub stringify {
        "DBICTest::Exception is handling this: " . shift->{msg};
    }
}

# Try the exception class
$schema->exception_action(sub { DBICTest::Exception->throw(@_) });
throws_ok \&$throw,
  qr/DBICTest::Exception is handling this: $ex_regex/;

# While we're at it, lets throw a custom exception through Storage::DBI
throws_ok { $schema->storage->throw_exception('floob') }
  qr/DBICTest::Exception is handling this: floob/;

# Exception class which stringifies to empty string
{
    package DBICTest::ExceptionEmptyString;
    use overload bool => sub { 1 }, '""' => sub { "" }, fallback => 1;
    sub new { bless {}, shift; }
}

# Try the exception-empty string class
$schema->exception_action(sub { die DBICTest::ExceptionEmptyString->new });
dies_ok \&$throw;

my $throw_x_empty_string  = sub { $schema->txn_do (sub { die DBICTest::ExceptionEmptyString->new }); };
$schema->exception_action(sub { die @_ });
dies_ok \&$throw_x_empty_string, 'exception_action handles exception object-empty string';
isa_ok $@, 'DBICTest::ExceptionEmptyString', "exception rethrown by exception_action";

done_testing;
