
my $dbic_ver_re = qr/ 0 \. (\d{2}) (\d{2}) (\d{2}) (?: _ (\d{2}) )? /x; # not anchored!!!

my $version_string = Meta->version;
my $version_value = eval $version_string;

my ($v_maj, $v_min, $v_point, $v_dev) = $version_string =~ /^$dbic_ver_re$/
  or die sprintf (
    "Invalid version %s (as specified in %s)\nCurrently valid version formats are 0.MMVVPP or 0.MMVVPP_DD\n",
    $version_string,
    Meta->{values}{version_from} || Meta->{values}{all_from} || 'Makefile.PL',
  )
;

if ($v_maj > 8) {
  die "Illegal version $version_string - we are still in the 0.08 cycle\n"
}

Meta->makemaker_args->{DISTVNAME} = Meta->name . "-$version_string-TRIAL" if (
  # all odd releases *after* 0.089x generate a -TRIAL, no exceptions
  ( $v_point > 89 )
);


my $tags = { map { chomp $_; $_ => 1} `git tag` };
# git may not be available
if (keys %$tags) {
  my $shipped_versions;
  my $shipped_dev_versions;

  my $legacy_re = qr/^ v 0 \. (\d{2}) (\d{2}) (\d) (?: _ (\d{2}) )? $/x;

  for (keys %$tags) {
    if ($_ =~ /^v$dbic_ver_re$/ or $_ =~ $legacy_re ) {
      if (defined $4) {
        $shipped_dev_versions->{"0.$1$2$3$4"} = 1;
      }
      else {
        $shipped_versions->{"0.$1$2$3"} = 1;
      }
      delete $tags->{$_};
    }
  }

  die sprintf "Tags in unknown format found: %s\n", join ', ', keys %$tags
    if keys %$tags;
}

# keep the Makefile.PL eval happy
1;
