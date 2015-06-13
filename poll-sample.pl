#!/usr/bin/perl -w

use strict;
use warnings;

use utf8;
use FindBin;
use lib $FindBin::Bin;

use wwwatchdog;

my $std_notifier = sub {
  my ($msg, $error) = @_;

  print "$msg\n$error\n";
};

my $cust_notifier = sub {
  my ($msg, $error) = @_;

  print "msg: $msg, err: $error\n";
};

=for comment

my $sns_notifier = sub {
  my ($msg, $error) = @_;

  my $endpoint = "http://sns.us-east-1.amazonaws.com/?";
  my $arn = "arn:aws:sns:us-east-1:<arn-num>:<arn-name>";
  $arn =~ s/:/%3A/g;
  my $aws_key_id = "<PLACEHOLDER>";
  my $aws_secret_key = "<PLACEHOLDER>";

  my $subj = "$msg";
  my $cont = "Reason : $error\n";

  use LWP::UserAgent;
  my $ua = new LWP::UserAgent;
  my $timestamp = POSIX::strftime("%Y-%m-%dT%H:%M:%S.000Z", gmtime());
  my $req = "${endpoint}Subject=$subj&TopicArn=$arn&Message=$cont&Action=Publish&SignatureVersion=2&SignatureMethod=HmacSHA256&Timestamp=$timestamp&AWSAccessKeyId=$aws_key_id";
  use Net::Amazon::AWSSign;
  my $as = new Net::Amazon::AWSSign("$aws_key_id", "$aws_secret_key");
  $req = $as->addRESTSecret($req);

  my $res = "";
  eval {$res = $ua->get($req)};
  return ref($res)?$res->decoded_content:"";
};

=cut

my %targets = (
  'http://www.google.com' => {
    'maintain_session' => 0,
    'notifier' => $cust_notifier,
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

wwwatchdog::process(\%targets, $std_notifier);
