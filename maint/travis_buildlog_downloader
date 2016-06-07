#!/usr/bin/env perl

use warnings;
use strict;

# H::T does not support gzip/deflate out of the box, but you know what?
# THAT'S OK BECAUSE TRAVIS' LOGSERVER DOESN'T EITHER </headdesk>
use HTTP::Tiny;

use JSON::PP;

( my $build_id = $ARGV[0]||'' ) =~ /^[0-9]+$/
  or die "Expecting a numeric build id as argument\n";

my $base_url = "http://api.travis-ci.org/builds/$build_id";
print "Retrieving $base_url\n";

my $resp = ( my $ua = HTTP::Tiny->new )->get( $base_url );
die "Unable to retrieve $resp->{url}: $resp->{status}\n$resp->{content}\n\n"
  unless $resp->{success};

my @job_ids = ( map
  { ($_->{id}||'') =~ /^([0-9]+)$/ }
  @{( eval { decode_json( $resp->{content} )->{matrix} } || [] )}
) or die "Unable to find any job ids:\n$resp->{content}\n\n";

my $dir = "TravisCI_build_$build_id";

mkdir $dir
  unless -d $dir;

for my $job_id (@job_ids) {
  my $log_url = "http://api.travis-ci.org/jobs/$job_id/log.txt";
  my $dest_fn = "$dir/job_$job_id.log";

  print "Retrieving $log_url into $dest_fn\n";

  $resp = $ua->mirror( $log_url, $dest_fn );
  warn "Error retrieving $resp->{url}: $resp->{status}\n$resp->{content}\n\n"
    unless $resp->{success};
}
