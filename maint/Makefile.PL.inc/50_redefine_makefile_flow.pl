# Split create_distdir into several subtargets, allowing us to generate
# stuff, inject it into lib/, manifest it, and then clean all of it up
{
  package MY;
  sub distdir {
    (my $snippet = shift->SUPER::distdir(@_)) =~ s/^create_distdir :/create_distdir_copy_manifested :/;
    return <<"EOM";
$snippet

.NOTPARALLEL :

create_distdir : check_create_distdir_prereqs clonedir_generate_files clonedir_post_generate_files fresh_manifest create_distdir_copy_manifested clonedir_cleanup_generated_files
\t\$(NOECHO) \$(NOOP)

clonedir_generate_files :
\t\$(NOECHO) \$(NOOP)

clonedir_post_generate_files :
\t\$(NOECHO) \$(NOOP)

clonedir_cleanup_generated_files :
\t\$(NOECHO) \$(NOOP)

check_create_distdir_prereqs :
\t\$(NOECHO) @{[
  $mm_proto->oneliner("DBIx::Class::Optional::Dependencies->die_unless_req_ok_for(q(dist_dir))", [qw/-Ilib -MDBIx::Class::Optional::Dependencies/])
]}

EOM
  }
}

# M::I inserts its own default postamble, so we can't easily override upload
# but we can still hook postamble in EU::MM
{
  package MY;

  sub postamble {
    my $snippet = shift->SUPER::postamble(@_);
    return <<"EOM";
$snippet

upload :: check_create_distdir_prereqs check_upload_dist_prereqs

check_upload_dist_prereqs :
\t\$(NOECHO) @{[
  $mm_proto->oneliner("DBIx::Class::Optional::Dependencies->die_unless_req_ok_for(q(dist_upload))", [qw/-Ilib -MDBIx::Class::Optional::Dependencies/])
]}

EOM
  }
}

# EU::MM BUG - workaround
# somehow the init_PM of EUMM (in MM_Unix) interprets ResultClass.pod.proto
# as a valid ResultClass.pod. While this has no effect on dist-building
# it royally screws up the local Makefile.PL $TO_INST_PM and friends,
# making it impossible to make/make test from a checkout
# just rip it out here (remember - this is only executed under author mode)
{
  package MY;
  sub init_PM {
    my $self = shift;
    my $rv = $self->SUPER::init_PM(@_);
    delete @{$self->{PM}}{qw(lib/DBIx/Class/Manual/ResultClass.pod lib/DBIx/Class/Manual/ResultClass.pod.proto)};
    $rv
  }
}

# make the install (and friends) target a noop - instead of
# doing a perl Makefile.PL && make && make install (which will leave pod
# behind), one ought to assemble a distdir first

{
  package MY;
  sub install {
    (my $snippet = shift->SUPER::install(@_))
      =~ s/^( (?: install [^\:]+ | \w+_install \s) \:+ )/$1 block_install_from_checkout/mxg;
    return <<"EOM";
$snippet

block_install_from_checkout :
\t\$(NOECHO) \$(ECHO) Installation directly from a checkout is not possible. You need to prepare a distdir, enter it, and run the installation from within.
\t\$(NOECHO) \$(FALSE)

EOM
  }
}

# keep the Makefile.PL eval happy
1;
