#############################################
# Tests for Sysadm::Install/s plough
#############################################

use Test::More tests => 4;

use Sysadm::Install qw(:all);

use File::Spec;
use File::Path;

my $TEST_DIR = ".";
$TEST_DIR = "t" if -d 't';

ok(1, "loading ok");

my $script  = 'print "$< rocks!\\n";';
my $escaped = qquote($script, '!$'); # Escape for shell use
my $out = `perl -e $escaped`;

is($out, "$< rocks!\n", "simple escape");

$escaped = qquote($script, '!$][)('); # Escape for shell use

    # shell escape
$escaped = qquote('[some]$thing(weird)"`', ":shell");
is($escaped, '"[some]\\$thing(weird)\\"\\`"', ":shell");

    # single quote
$escaped = quote("[some]\$thing(weird)'`");
is($escaped, "'[some]\$thing(weird)\\'`'", "single quote");
