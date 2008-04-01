use inc::Module::Install 0.67;

name     'DBIx-Class';
perl_version '5.006001';
all_from 'lib/DBIx/Class.pm';

requires 'Data::Page'                => 2.00;
requires 'Scalar::Util'              => 0;
requires 'SQL::Abstract'             => 1.20;
requires 'SQL::Abstract::Limit'      => 0.101;
requires 'Class::C3'                 => 0.13;
requires 'Class::C3::Componentised'  => 0;
requires 'Storable'                  => 0;
requires 'Carp::Clan'                => 0;
requires 'DBI'                       => 1.40;
requires 'Module::Find'              => 0;
requires 'Class::Inspector'          => 0;
requires 'Class::Accessor::Grouped'  => 0.05002;
requires 'JSON::Any'                 => 1.00; 
requires 'Scope::Guard'              => 0.03;
requires 'Digest::SHA1'              => 2.00;

# Perl 5.8.0 doesn't have utf8::is_utf8()
requires 'Encode'                    => 0 if ($] <= 5.008000);  

build_requires 'DBD::SQLite'         => 1.13;
build_requires 'Test::Builder'       => 0.33;
build_requires 'Test::Warn'          => 0.08;
build_requires 'Test::NoWarnings'    => 0.08;

install_script 'script/dbicadmin';

tests "t/*.t t/*/*.t";

# re-build README and require CDBI modules for testing if we're in a checkout
if( -e 'inc/.author' ) {
  build_requires 'DBIx::ContextualFetch';
  build_requires 'Class::Trigger';
  build_requires 'Time::Piece';

  system('pod2text lib/DBIx/Class.pm > README');
}

auto_provides;

auto_install;

WriteAll;


if ($Module::Install::AUTHOR) {
  # Need to do this _after_ WriteAll else it looses track of them
  Meta->{values}{build_requires} = [ grep {
    $_->[0] !~ /
      DBIx::ContextualFetch |
      Class::Trigger |
      Time::Piece
    /x;
  } @{Meta->{values}{build_requires}} ];

  my @scalar_keys = Module::Install::Metadata::Meta_TupleKeys();
  sub Module::Install::Metadata::Meta_TupleKeys {
    return @scalar_keys, 'resources';
  }
  Meta->{values}{resources} = [ 
    [ 'MailingList', 'http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/dbix-class' ],
    [ 'IRC', 'irc://irc.perl.org/#dbix-class' ],
  ];
  Meta->write;
}



