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
  my ($targets, $default_notifier, $get_ua) = @_;
  my %targets = %$targets;

  my $log_time = strftime("%Y%m%d%H%M%S", localtime());

  foreach my $base_url (keys %targets) {
    (my $domain = $base_url) =~ s!^\s*https?://!!;
    my $notifier = (ref($targets{$base_url}{notifier}) eq 'CODE')?$targets{$base_url}{notifier}:$default_notifier;
    $domain =~ s!/+$!!;
    my $error = "";
    my $slow = 0;
    my $ua = (ref($get_ua)?&$get_ua():(new LWP::UserAgent));
    $ua->agent("wwwatchdog/1.0");
    $ua->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
    if ($targets{$base_url}{maintain_session}) {
      $ua->cookie_jar({});
    }
    foreach my $uri (keys %{$targets{$base_url}{uris}}) {
      my ($html, $response_time, $resp);

      our $res_has_timedout = 0;
      my $timeout_val = ($targets{$base_url}{uris}{$uri}{time_threshold} || 1) + 1;
      use POSIX ':signal_h';
      my $newaction = POSIX::SigAction->new(
        sub { $res_has_timedout = 1; die "web request timeout"; },
        POSIX::SigSet->new(SIGALRM)
      );

      my $oldaction = POSIX::SigAction->new();
      if(!sigaction(SIGALRM, $newaction, $oldaction)) {
        $error .= "Error setting SIGALRM handler: $!\n";
      }

      eval {
        $ua->timeout($timeout_val);
        alarm($timeout_val);
        my $start = Time::HiRes::gettimeofday();
        $resp = $ua->get("${base_url}$uri");
        $html = $resp->decoded_content;
        my $time = Time::HiRes::gettimeofday();
        $response_time = $time - $start;
        alarm(0);
      };
      my $ua_exception = $@;
      alarm(0);
      if(!sigaction(SIGALRM, $oldaction )) {
        $error .= "Error resetting SIGALRM handler: $!\n";
      }
      if ($ua_exception) {
        if ($ua_exception =~ m!timeout!i) {
          $error .= "${base_url}$uri timed out\n";
        }
        else {
          $error .= "error getting ${base_url}$uri : $ua_exception\n";
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
          foreach my $r_name (keys %{$targets{$base_url}{uris}{$uri}{html_regexps}}) {
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
      &$notifier("$domain stopped functioning", $error);
    }
    if ($prev_error && !$error) {
      unlink(dirname(__FILE__)."/error_flag_${domain}");
      &$notifier("$domain restored functioning", "");
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
        &$notifier("$domain works slow for $slowness_period_threshold consequtive minutes", "");
      }
    }
  }
}


1;
