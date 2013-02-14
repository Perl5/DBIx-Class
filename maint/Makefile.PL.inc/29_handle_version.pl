
my $dbic_ver_re = qr/ (\d) \. (\d{2}) (\d{3}) (?: _ (\d{2}) )? /x; # not anchored!!!

my $version_string = Meta->version;
my $version_value = eval $version_string;

my ($v_maj, $v_min, $v_point, $v_dev) = $version_string =~ /^$dbic_ver_re$/
  or die sprintf (
    "Invalid version %s (as specified in %s)\nCurrently valid version formats are M.VVPPP or M.VVPPP_DD\n",
    $version_string,
    Meta->{values}{version_from} || Meta->{values}{all_from} || 'Makefile.PL',
  )
;

if ($v_maj != 0 or $v_min > 8) {
  die "Illegal version $version_string - we are still in the 0.08 cycle\n"
}

if ($v_point >= 300) {
  die "Illegal version $version_string - we are still in the 0.082xx cycle\n"
}

Meta->makemaker_args->{DISTVNAME} = Meta->name . "-$version_string-TRIAL" if (
  # 0.08240 ~ 0.08249 shall be TRIALs for the collapser rewrite
  ( $v_point >= 240  and $v_point <= 249 )
    or
  # all odd releases *after* 0.08200 generate a -TRIAL, no exceptions
  ( $v_point > 200 and int($v_point / 100) % 2 )
);


my $tags = { map { chomp $_; $_ => 1} `git tag` };
# git may not be available
if (keys %$tags) {
  my $shipped_versions;
  my $shipped_dev_versions;

  for (keys %$tags) {
    if ($_ =~ /^v$dbic_ver_re$/) {
      if (defined $4) {
        $shipped_dev_versions->{"$1.$2$3$4"} = 1;
      }
      else {
        $shipped_versions->{"$1.$2$3"} = 1;
      }
      delete $tags->{$_};
    }
  }

  die sprintf "Tags in unknown format found: %s\n", join ', ', keys %$tags
    if keys %$tags;
}

# keep the Makefile.PL eval happy
1;
