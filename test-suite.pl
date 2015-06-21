#!/usr/bin/perl -w

use strict;
use warnings;

`rm -f ./error_flag_*`;
`rm -f ./slow_flag_*`;

use Test::More;
use Test::LWP::UserAgent;

use_ok('wwwatchdog');

my $msg;
my $ntf = sub {
  my ($title, $err) = @_;
  $title //= ''; $err //= '';
  $msg = "$title;$err";
};

###

my $targets = {
  'http://www.test' => {
    'uris' => {
      '/' => {
      }
    }
  }
};

my $ua = new Test::LWP::UserAgent;
$ua->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));

$msg = ""; wwwatchdog::process($targets, $ntf, $ua);
ok($msg eq '', "Base case scenario.");

### 

my $targets_length = {
  'http://www.test' => {
    'uris' => {
      '/' => {
        'length_threshold' => 1024,
      }
    }
  }
};

my $ua_length = new Test::LWP::UserAgent;
$ua_length->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));

$msg = ""; wwwatchdog::process($targets_length, $ntf, $ua_length);
like($msg, qr{length is less than expected}, "Length threshold. Negative part.");


$ua_length = new Test::LWP::UserAgent;
$ua_length->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], 'X'x2048));

$msg = ""; wwwatchdog::process($targets_length, $ntf, $ua_length);
like($msg, qr{restored functioning}, "Length threshold. Positive part.");

###

my $targets_status = {
  'http://www.test' => {
    'uris' => {
      '/' => {
        'target_status' => 404,
      }
    }
  }
};

my $ua_status = new Test::LWP::UserAgent;
$ua_status->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));

$msg = ""; wwwatchdog::process($targets_status, $ntf, $ua_status);
like($msg, qr{status differs from expected}, "Page status check. Negative part.");


$ua_status = new Test::LWP::UserAgent;
$ua->map_response('www.test', HTTP::Response->new('404', 'Not Found', ['Content-Type' => 'text/plain'], ''));

$msg = ""; wwwatchdog::process($targets_status, $ntf, $ua_status);
like($msg, qr{restored functioning}, "Page status check. Positive part.");


###

my $targets_complex = {
  'http://www.test' => {
    'uris' => {
      '/' => {
        'length_threshold' => 1024,
        'html_regexps' => {
          '1' => qr{XXXXX},
        }
      }
    }
  }
};

$ua_length = new Test::LWP::UserAgent;
$ua_length->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], 'X'x512));

$msg = ""; wwwatchdog::process($targets_complex, $ntf, $ua_length);
like($msg, qr{length is less than expected}, "Complex test. First negative part.");

$ua_length = new Test::LWP::UserAgent;
$ua_length->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], 'Y'x2048));

$msg = ""; wwwatchdog::process($targets_complex, $ntf, $ua_length);
ok($msg eq '', "Complex test. Second negative part.");

$ua_length = new Test::LWP::UserAgent;
$ua_length->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], 'X'x2048));

$msg = ""; wwwatchdog::process($targets_complex, $ntf, $ua_length);
like($msg, qr{restored functioning}, "Complex test. Positive part.");

###

my $ua_regexp = new Test::LWP::UserAgent;
$ua_regexp->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], 'Y'x2048));

$msg = ""; wwwatchdog::process($targets_complex, $ntf, $ua_regexp);
like($msg, qr{doesn't match .+ regexp}, "Regexp test. Negative part.");

$ua_regexp = new Test::LWP::UserAgent;
$ua_regexp->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], 'X'x2048));

$msg = ""; wwwatchdog::process($targets_complex, $ntf, $ua_regexp);
like($msg, qr{restored functioning}, "Regexp test. Positive part.");

###

my $targets_slow = {
  'http://www.test' => {
    'slowness_period_threshold' => 0,
    'uris' => {
      '/' => {
        'time_threshold' => 1,
      }
    }
  }
};

my $ua_slow = new Test::LWP::UserAgent;
$ua_slow->map_response(sub {
  sleep 1.5;
  return 1;
}, HTTP::Response->new('200'));

$msg = ""; wwwatchdog::process($targets_slow, $ntf, $ua_slow);
ok($msg eq '', "Slowness test. Pre-negative part.");

sleep 1;

$msg = ""; wwwatchdog::process($targets_slow, $ntf, $ua_slow);
like($msg, qr{works slow}, "Slowness test. Negative part.");

$ua = new Test::LWP::UserAgent;
$ua->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));

$msg = ""; wwwatchdog::process($targets_slow, $ntf, $ua);
ok($msg eq '', "Slowness test. Positive part.");

###

done_testing;
