=head1 wwwatchdog.pm

The library is intended to facilitate web site availability checks. It processes a list of base URLs and URIs to visit, reports problems detected (broken or slow pages). 

It's supposed to be used in inversion of control environment, i.e. there's a controller script defining the lists to process and the notificaton routines, it then calls wwwatchdog::process subroutine to perform actions (URL checks and customer notifications) based on those lists. A sample of controller script can be seen in poll-sample.pl, test-suite.pl can be run to check wwwatchdog.pm proper functioning.

The controller script is meant to be put in crontab with short interval (like run every 5 minutes). 

=cut


package wwwatchdog;

use strict;
use warnings;

use LWP::UserAgent;
use Time::Local;
use Time::HiRes;
use POSIX;
use File::Basename;

=head3 init_ua()

The subroutine does additional initialization to a LWP::UserAgent object (it sets some default headers and creates a cookie jar if requested). It's used in a few places in the L</"process()"> function .

Arguments:

=over

=item $ua - LWP::UserAgent or derivative object to perform the initialization on.

=item $session_support (boolean) - whether to initialize cookie jar or not.

=back

=cut

sub init_ua {
  my ($ua, $session_support) = @_;
  $ua->agent("wwwatchdog/1.0");
  $ua->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
  if ($session_support) {
    $ua->cookie_jar({});
  }
}

=head3 process()

The main function that performs actions as prescribed by controller script. 

Arguments:

=over

=item $targets (hashref) - the list of URLs and URIs to process. It's stuctured as a nested tree and is of complex stucture. See poll-sample.pl for ideas on how to make it up for your needs.

=item $default_notifier (sub ref) - a function taking two params (Subject and Message) and reporting them to the script customer (by sending an e-mail or other means). It's supposed to be defined in the controller script. It can be overridden on per-URL basis in $targets param.

=item $custom_ua (Test::LWP::UserAgent object of sub ref, optional) - the script allows to override the UserAgent object for automated testing purposes.

=back

=cut

sub process {
  my ($targets, $default_notifier, $custom_ua) = @_;
  my %targets = %$targets;

  my $log_time = strftime("%Y%m%d%H%M%S", localtime());

  foreach my $base_url (keys %targets) {
    (my $domain = $base_url) =~ s!^\s*https?://!!;
    my $notifier = (ref($targets{$base_url}{notifier}) eq 'CODE')?$targets{$base_url}{notifier}:$default_notifier;
    $domain =~ s!/+$!!;
    my $error = "";
    my $slow = 0;
    my $ua = (ref($custom_ua) eq "Test::LWP::UserAgent")?$custom_ua:(new LWP::UserAgent);
    init_ua($ua, $targets{$base_url}{maintain_session});
    foreach my $uri (keys %{$targets{$base_url}{uris}}) {
      my ($html, $response_time, $resp);

      my $timeout_val = ($targets{$base_url}{uris}{$uri}{time_threshold} || 1) + 1;
      my $repeats = 0;

      my ($uri_error, $uri_slow) = ("", 0);
      do {
        ($uri_error, $uri_slow) = ("", 0);
        our $res_has_timedout = 0;
        use POSIX ':signal_h';
        my $newaction = POSIX::SigAction->new(
          sub { $res_has_timedout = 1; die "web request timeout"; },
          POSIX::SigSet->new(SIGALRM)
        );

        my $oldaction = POSIX::SigAction->new();
        if(!sigaction(SIGALRM, $newaction, $oldaction)) {
          $uri_error .= "Error setting SIGALRM handler: $!\n";
        }

        eval {
          if (ref($custom_ua) eq 'CODE') {
            $ua = &$custom_ua();
            init_ua($ua, $targets{$base_url}{maintain_session});
          }
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
          $uri_error .= "Error resetting SIGALRM handler: $!\n";
        }
        if ($ua_exception) {
          if ($ua_exception =~ m!timeout!i) {
            $uri_error .= "${base_url}$uri timed out\n";
          }
          else {
            $uri_error .= "error getting ${base_url}$uri : $ua_exception\n";
          }
        }
        else {
          my $target_status = $targets{$base_url}{uris}{$uri}{target_status} || '200';
          if ($resp->status_line !~ m!$target_status!) {
            $uri_error .= "${base_url}$uri status differs from expected ('".$resp->status_line."' vs. '$target_status')\n";
          }
          if ($targets{$base_url}{uris}{$uri}{length_threshold} && length($html) < $targets{$base_url}{uris}{$uri}{length_threshold}) {
            $uri_error .= "${base_url}$uri length is less than expected (".length($html)." < ".$targets{$base_url}{uris}{$uri}{length_threshold}.")\n";
          }
          if (!$uri_error && ref($targets{$base_url}{uris}{$uri}{html_regexps}) eq 'HASH') {
            foreach my $r_name (keys %{$targets{$base_url}{uris}{$uri}{html_regexps}}) {
              my $r = $targets{$base_url}{uris}{$uri}{html_regexps}{$r_name};
              if ($html !~ m/$r/) {
                $uri_error .= "${base_url}$uri doesn't match '$r_name' regexp\n";
              }
            }
          }
          if ($response_time > ($targets{$base_url}{uris}{$uri}{time_threshold} || 1)) {
            $uri_slow = 1;
          }
        }
      } until (!$targets{$base_url}{repeat_on_error} || !($uri_error || $uri_slow) || ++$repeats > 1 );
      $error .= $uri_error;
      $slow ||= $uri_slow;
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
    elsif (!$error && $slow && $prev_slow) {
      my $slowness_period_threshold = ($targets{$base_url}{slowness_period_threshold} // 5);
      if ((stat(dirname(__FILE__)."/slow_flag_${domain}"))[9] < timelocal(localtime()) - ($slowness_period_threshold * 60 - 5 )) {
        &$notifier("$domain works slow for $slowness_period_threshold consequtive minutes", "");
      }
    }
  }
}


1;

=head2 author

Victor Ichalov <ichalov@gmail.com>, 2015.

=cut

