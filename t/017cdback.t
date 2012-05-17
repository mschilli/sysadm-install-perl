use Test::More;

use Sysadm::Install qw(:all);
use Cwd;
use File::Temp qw( tempdir );

my $dir_a = tempdir( CLEANUP => 1 );
my $dir_b = tempdir( CLEANUP => 1 );

plan tests => 4;

my $org = cwd();

cd $dir_a;
cd $dir_b;

is cwd(), $dir_b, "dir b";
cdback;
is cwd(), $dir_a, "back to dir a";
cdback;
is cwd(), $org, "back to dir a";

cd $dir_a;
cd $dir_b;

cdback( { reset => 1 } );
is cwd(), $org, "reset";
