#####################################
# Tests for Sysadm::Install
#####################################

use Test::More tests => 1;
use Sysadm::Install qw(:all);

eval {
   download "file:///very/unlikely/that/this/file/exists";
};

ok $@, "download of non-existent file";
