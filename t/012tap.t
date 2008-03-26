#####################################
# Tests for Sysadm::Install
#####################################

use Test::More tests => 1;

use Sysadm::Install qw(:all);

my($stdout, $stderr, $rc) = tap "echo", "'";
is($stdout, "'\n", "single quoted tap");
