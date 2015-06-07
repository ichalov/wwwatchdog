# Author: Victor Ichalov <ichalov@gmail.com>, 2015

package wwwatchdog;

use strict;
use warnings;

use LWP::UserAgent;
use Time::Local;
use Time::HiRes;
use POSIX;
use File::Basename;


sub process {
  my ($targets, $sendmail) = @_;
  my %targets = %$targets;

  $SIG{ALRM} = sub { die "timeout" };

  my $log_time = strftime("%Y%m%d%H%M%S", localtime());

  foreach my $base_url (keys %targets) {
    (my $domain = $base_url) =~ s!^\s*https?://!!;
    $domain =~ s!/+$!!;
    my $error = "";
    my $slow = 0;
    my $ua = new LWP::UserAgent;
    $ua->agent("wwwatchdog/1.0");
    $ua->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
    if ($targets{$base_url}{maintain_session}) {
      $ua->cookie_jar({});
    }
    foreach my $uri (keys $targets{$base_url}{uris}) {
      my ($html, $response_time, $resp);
      eval {
        alarm(($targets{$base_url}{uris}{$uri}{time_threshold} || 1) + 1);
        my $start = Time::HiRes::gettimeofday();
        $resp = $ua->get("${base_url}$uri");
        $html = $resp->decoded_content;
        my $time = Time::HiRes::gettimeofday();
        $response_time = $time - $start;
        alarm(0);
      };
      if ($@) {
        if ($@ =~ m!timeout!i) {
          $error = "${base_url}$uri timed out\n";
        }
        else {
          $error = "error getting ${base_url}$uri : $@\n";
        }
      }
      else {
        my $target_status = $targets{$base_url}{uris}{$uri}{target_status} || '200';
        if ($resp->status_line !~ m!$target_status!) {
          $error .= "${base_url}$uri status differs from expected ('".$resp->status_line."' vs. '$target_status')\n";
        }
        if ($targets{$base_url}{uris}{$uri}{length_threshold} && length($html) < $targets{$base_url}{uris}{$uri}{length_threshold}) {
          $error .= "${base_url}$uri length is less than expected (".length($html)." < ".$targets{$base_url}{uris}{$uri}{length_threshold}.")\n";
        }
        if (!$error && ref($targets{$base_url}{uris}{$uri}{html_regexps}) eq 'HASH') {
          foreach my $r_name (keys $targets{$base_url}{uris}{$uri}{html_regexps}) {
            my $r = $targets{$base_url}{uris}{$uri}{html_regexps}{$r_name};
            if ($html !~ m/$r/) {
              $error .= "${base_url}$uri doesn't match '$r_name' regexp\n"; 
            }
          }
        }
        if ($response_time > ($targets{$base_url}{uris}{$uri}{time_threshold} || 1)) {
          $slow = 1;
        }
      }
    }

    my $prev_error = -f dirname(__FILE__)."/error_flag_${domain}";
    if (!$prev_error && $error) {
      open my $f, ">", dirname(__FILE__)."/error_flag_${domain}";
      print $f $log_time;
      close $f;
      &$sendmail("$domain stopped functioning", $error);
    }
    if ($prev_error && !$error) {
      unlink(dirname(__FILE__)."/error_flag_${domain}");
      &$sendmail("$domain restored functioning", "");
    }

    my $prev_slow = -f dirname(__FILE__)."/slow_flag_${domain}";
    if (!$slow && $prev_slow) {
      unlink(dirname(__FILE__)."/slow_flag_${domain}");
    }
    elsif ($slow && !$prev_slow) {
      open my $f, ">", dirname(__FILE__)."/slow_flag_${domain}";
      print $f $log_time;
      close $f;
    }
    elsif ($slow && $prev_slow) {
      my $slowness_period_threshold = ($targets{$base_url}{slowness_period_threshold} // 5);
      if ((stat(dirname(__FILE__)."/slow_flag_${domain}"))[9] < timelocal(localtime()) - ($slowness_period_threshold * 60 - 5 )) {
        &$sendmail("$domain works slow for $slowness_period_threshold consequtive minutes", "");
      }
    }
  }
}


1;
