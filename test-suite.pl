#!/usr/bin/perl -w

use strict;
use warnings;

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
  'http://www.google.com' => {
    'uris' => {
      '/' => {
      }
    }
  }
};

my $get_ua = sub {
  use Test::LWP::UserAgent;
  my $ua = new Test::LWP::UserAgent;

  $ua->map_response('www.google.com', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));

  return $ua;
};

$msg = ""; wwwatchdog::process($targets, $ntf, $get_ua);
ok($msg eq '', "Base case scenario.");

### 

my $targets_length = {
  'http://www.google.com' => {
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
      $ua->map_response('www.google.com', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], ''));
    }
    else {
      $ua->map_response('www.google.com', HTTP::Response->new('200', 'OK', ['Content-Type' => 'text/plain'], 'X'x2048));
    }

    return $ua;
  };
}

$msg = ""; wwwatchdog::process($targets_length, $ntf, $get_ua_length);
like($msg, qr{length is less than expected}, "Length threshold. Negative part.");

$msg = ""; wwwatchdog::process($targets_length, $ntf, $get_ua_length);
like($msg, qr{restored functioning}, "Length threshold. Positive part.");

###


done_testing;
