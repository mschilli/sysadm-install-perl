#####################################
# Tests for Sysadm::Install
#####################################

use Test::More tests => 2;

use Sysadm::Install qw(:all);

SKIP: {
  skip "echo not supported on Win32", 2 if $^O eq "MSWin32";
  my($stdout, $stderr, $rc) = tap "echo", "'";
  is($stdout, "'\n", "single quoted tap");

  ($stdout, $stderr, $rc) = tap { raise_error => 1 }, "echo";
  is($rc, 0, "tap and raise");
}
