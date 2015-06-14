#!/usr/bin/perl -w

use strict;
use warnings;

`rm -f ./error_flag_*`;
`rm -f ./slow_flag_*`;

use Test::More;

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

my $get_ua = sub {
  use Test::LWP::UserAgent;
  my $ua = new Test::LWP::UserAgent;

  $ua->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));

  return $ua;
};

$msg = ""; wwwatchdog::process($targets, $ntf, $get_ua);
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

my $get_ua_length;
{
  my $cnt;
  $get_ua_length = sub {
    use Test::LWP::UserAgent;

    my $ua = new Test::LWP::UserAgent;
    if (++$cnt == 1) {
      $ua->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));
    }
    else {
      $ua->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], 'X'x2048));
    }

    return $ua;
  };
}

$msg = ""; wwwatchdog::process($targets_length, $ntf, $get_ua_length);
like($msg, qr{length is less than expected}, "Length threshold. Negative part.");

$msg = ""; wwwatchdog::process($targets_length, $ntf, $get_ua_length);
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

my $get_ua_status;
{
  my $cnt;
  $get_ua_status = sub {
    use Test::LWP::UserAgent;

    my $ua = new Test::LWP::UserAgent;
    if (++$cnt == 1) {
      $ua->map_response('www.test', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));
    }
    else {
      $ua->map_response('www.test', HTTP::Response->new('404', 'Not Found', ['Content-Type' => 'text/plain'], ''));
    }

    return $ua;
  };
}

$msg = ""; wwwatchdog::process($targets_status, $ntf, $get_ua_status);
like($msg, qr{status differs from expected}, "Page status check. Negative part.");

$msg = ""; wwwatchdog::process($targets_status, $ntf, $get_ua_status);
like($msg, qr{restored functioning}, "Page status check. Positive part.");


###

done_testing;
