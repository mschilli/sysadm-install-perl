#############################################
# Tests for Sysadm::Install/s fs_read/write_open
#############################################

use Test::More tests => 5;

use Sysadm::Install qw(:all);

is(snip("abc", 5), 
   "(3)[abc]", "snip full len");

is(snip("abcdefghijklmn", 11), 
   "(14)[ab[snip=10]mn]", "snip minlen");

is(snip("abcdefghijklmn", 12), 
   "(14)[ab[snip=10]mn]", "snip minlen");

is(snip("a\tcdefghijklm\n", 12), 
   "(14)[a.[snip=10]m.]", "snip special char");

is(snip("a\tcdefghijklm\n", 14), 
   "(14)[a.cdefghijklm.]", "exact len match")
