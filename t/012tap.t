#####################################
# Tests for Sysadm::Install
#####################################

use Test::More tests => 1;

use Sysadm::Install qw(:all);

SKIP: {
  skip "echo not supported on Win32", 1 if $^O eq "MSWin32";
  my($stdout, $stderr, $rc) = tap "echo", "'";
  is($stdout, "'\n", "single quoted tap");
}
