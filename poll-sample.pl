#!/usr/bin/perl -w

use strict;
use warnings;

use utf8;
use FindBin;
use lib $FindBin::Bin;

use wwwatchdog;

my %targets = (
  'http://www.google.com' => {
    'maintain_session' => 0,
    'uris' => {
      '/' => {
        'length_threshold' => 1024,
        'target_status' => 200,
      }
    }
  },
  'https://www.google.ru' => {
    'maintain_session' => 1,
    'slowness_period_threshold' => 10,
    'uris' => {
      '/' => {
        'time_threshold' => 1,
        'length_threshold' => 1024,
        'target_status' => 200,
        'html_regexps' => {
          'js' => qr{onload="window.lol&&lol\(\)">},
          'copyright' => qr{&copy; \d+ - <a href="/intl/ru/policies/privacy/">},
        }
      }
    }
  },
);

my $sendmail = sub {
  my ($msg, $error) = @_;

  print "$msg\n$error\n";
};

wwwatchdog::process(\%targets, $sendmail);
