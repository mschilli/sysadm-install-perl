###############################################
package Sysadm::Install;
###############################################

use 5.006;
use strict;
use warnings;

our $VERSION = '0.22';

use File::Copy;
use File::Path;
use Log::Log4perl qw(:easy);
use Log::Log4perl::Util;
use LWP::Simple;
use File::Basename;
use File::Spec::Functions qw(rel2abs abs2rel);
use Cwd;
use File::Temp;

our $DRY_RUN;
our $CONFIRM;
our $DRY_RUN_MSG;
our $DATA_SNIPPED_LEN = 60;

dry_run(0);
confirm(0);

###############################################
sub dry_run {
###############################################
    my($on) = @_;

    if($on) {
        $DRY_RUN     = 1;
        $DRY_RUN_MSG = "(skipped - dry run)";
    } else {
        $DRY_RUN     = 0;
        $DRY_RUN_MSG = "";
    }
}

###############################################
sub confirm {
###############################################
    my($on) = @_;

    $CONFIRM = $on;
}

###########################################
sub _confirm {
###########################################
    my($msg) = @_;

    if($DRY_RUN) {
        INFO "$msg $DRY_RUN_MSG";
        return 0 if $DRY_RUN;
    }

    if($CONFIRM) {
        my $answer = ask("$msg ([y]/n)", "y");
        if($answer =~ /^\s*y\s*$/) {
            INFO $msg;
            return 1;
        }

        INFO "$msg (*CANCELLED* as requested)";
        return 0;
    }

    return 1;
}

our @EXPORTABLE = qw(
cp rmf mkd cd make 
cdback download untar 
pie slurp blurt mv tap 
plough qquote quote perm_cp
sysrun untar_in pick ask
hammer say
sudo_me bin_find
fs_read_open fs_write_open pipe_copy
snip
);

our %EXPORTABLE = map { $_ => 1 } @EXPORTABLE;

our @DIR_STACK;

##################################################
sub import {
##################################################
    my($class) = shift;

    no strict qw(refs);

    my $caller_pkg = caller();

    my(%tags) = map { $_ => 1 } @_;

        # Export all
    if(exists $tags{':all'}) {
        %tags = map { $_ => 1 } @EXPORTABLE;
    }

    for my $func (keys %tags) {
        LOGDIE __PACKAGE__ . 
            "doesn't export \"$func\"" unless exists $EXPORTABLE{$func};
        *{"$caller_pkg\::$func"} = *{$func};
    }
}

=pod

=head1 NAME

Sysadm::Install - Typical installation tasks for system administrators

=head1 SYNOPSIS

  use Sysadm::Install qw(:all);

  my $INST_DIR = '/home/me/install/';

  cd($INST_DIR);
  cp("/deliver/someproj.tgz", ".");
  untar("someproj.tgz");
  cd("someproj");

     # Write out ...
  blurt("Builder: Mike\nDate: Today\n", "build.dat");

     # Slurp back in ...
  my $data = slurp("build.dat");

     # or edit in place ...
  pie(sub { s/Today/scalar localtime()/ge; $_; }, "build.dat");

  make("test install");

     # run a cmd and tap into stdout and stderr
  my($stdout, $stderr, $exit_code) = tap("ls", "-R");

=head1 DESCRIPTION

Have you ever wished for your installation shell scripts to run
reproducably, without much programming fuzz, and even with optional
logging enabled? Then give up shell programming, use Perl.

C<Sysadm::Install> executes shell-like commands performing typical
installation tasks: Copying files, extracting tarballs, calling C<make>.
It has a C<fail once and die> policy, meticulously checking the result
of every operation and calling C<die()> immeditatly if anything fails.

C<Sysadm::Install> also supports a I<dry_run> mode, in which it 
logs everything, but suppresses any write actions. Dry run mode
is enabled by calling C<Sysadm::Install::dry_run(1)>. To switch
back to normal, call C<Sysadm::Install::dry_run(0)>.

As of version 0.17, C<Sysadm::Install> supports a I<confirm> mode,
in which it interactively asks the user before running any of its
functions (just like C<rm -i>). I<confirm> mode is enabled by calling 
C<Sysadm::Install::confirm(1)>. To switch
back to normal, call C<Sysadm::Install::confirm(0)>.

C<Sysadm::Install> is fully Log4perl-enabled. To start logging, just
initialize C<Log::Log4perl>. C<Sysadm::Install> acts as a wrapper class,
meaning that file names and line numbers are reported from the calling
program's point of view.

=head2 FUNCTIONS

=over 4

=cut

=pod

=item C<cp($source, $target)>

Copy a file from C<$source> to C<$target>. C<target> can be a directory.
Note that C<cp> doesn't copy file permissions. If you want the target
file to reflect the source file's user rights, use C<perm_cp()>
shown below.

=cut

###############################################
sub cp {
###############################################

    local($Log::Log4perl::caller_depth) += 1;

    _confirm("cp $_[0] $_[1]") or return 1;

    INFO "cp $_[0] $_[1]";

    File::Copy::copy @_ or 
        get_logger("")->logcroak("Cannot copy $_[0] to $_[1] ($!)");
}

=pod

=item C<mv($source, $target)>

Move a file from C<$source> to C<$target>. C<target> can be a directory.

=cut

###############################################
sub mv {
###############################################

    local($Log::Log4perl::caller_depth) += 1;

    _confirm("mv $_[0] $_[1]") or return 1;

    INFO "mv $_[0] $_[1]";

    File::Copy::move @_ or 
        get_logger("")->logcroak("Cannot move $_[0] to $_[1] ($!)");
}

=pod

=item C<download($url)>

Download a file specified by C<$url> and store it under the
name returned by C<basename($url)>.

=cut

###############################################
sub download {
###############################################

    local($Log::Log4perl::caller_depth) += 1;

    INFO "download $_[0]";

    _confirm("Downloading $_[0] => ", basename($_[0])) or return 1;

    getstore($_[0], basename($_[0])) or 
        get_logger("")->logcroak("Cannot download $_[0] ($!)");
}

=pod

=item C<untar($tarball)>

Untar the tarball in C<$tarball>, which typically adheres to the
C<someproject-X.XX.tgz> convention. 
But regardless of whether the 
archive actually contains a top directory C<someproject-X.XX>,
this function will behave if it had one. If it doesn't have one,
a new directory is created before the unpacking takes place. Unpacks
the tarball into the current directory, no matter where the tarfile
is located. 
Please note that if you're
using a compressed tarball (.tar.gz or .tgz), you'll need
IO::Zlib installed. 

=cut

###############################################
sub untar {
###############################################
    local($Log::Log4perl::caller_depth) += 1;

    get_logger("")->logcroak("untar called without defined tarfile") unless 
         @_ == 1 and defined $_[0];

    _confirm "untar $_[0]" or return 1;

    my($nice, $topdir, $namedir) = archive_sniff($_[0]);

    check_zlib($_[0]);
    require Archive::Tar;
    my $arch = Archive::Tar->new($_[0]);

    if($nice and $topdir eq $namedir) {
        DEBUG "Nice archive, extracting to subdir $topdir";
        rmf($namedir);
        $arch->extract();
    } elsif($nice) {
        DEBUG "Not-so-nice archive topdir=$topdir namedir=$namedir";
        rmf($namedir);
        rmf($topdir);
            # extract as topdir
        $arch->extract();
        rename $topdir, $namedir or 
            get_logger("")->logcroak("Can't rename $topdir, $namedir");
    } else {
        get_logger("")->logcroak("no topdir") unless defined $topdir;
        DEBUG "Not-so-nice archive (no topdir), extracting to subdir $topdir";
        $topdir = basename $topdir;
        rmf($topdir);
        mkd($topdir);
        cd($topdir);
        $arch->extract();
        cdback();
    }

    return $topdir;
}

=pod

=item C<untar_in($tar_file, $dir)>

Untar the tarball in C<$tgz_file> in directory C<$dir>. Create
C<$dir> if it doesn't exist yet.

=cut

###############################################
sub untar_in {
###############################################
    my($tar_file, $dir) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    get_logger("")->logcroak("not enough arguments") if
      ! defined $tar_file or ! defined $dir;

    _confirm "Untarring $tar_file in $dir" or return 1;

    mkd($dir) unless -d $dir;

    my $tar_file_abs = rel2abs($tar_file);

    cd($dir);

    check_zlib($tar_file_abs);
    require Archive::Tar;
    my $arch = Archive::Tar->new("$tar_file_abs");
    $arch->extract() or 
        get_logger("")->logcroak("Extract failed: $!");
    cdback();
}

=pod

=item C<pick($prompt, $options, $default)>

Ask the user to pick an item from a displayed list. C<$prompt>
is the text displayed, C<$options> is a referenc to an array of
choices, and C<$default> is the number (starting from 1, not 0)
of the default item. For example,

    pick("Pick a fruit", ["apple", "pear", "pineapple"], 3);

will display the following:

    [1] apple
    [2] pear
    [3] pineapple
    Pick a fruit [3]>

If the user just hits I<Enter>, "pineapple" (the default value) will
be returned. Note that 3 marks the 3rd element of the list, and is
I<not> an index value into the array.

If the user enters C<1>, C<2> or C<3>, the corresponding text string
(C<"apple">, C<"pear">, C<"pineapple"> will be returned by
C<pick()>.

=cut

##################################################
sub pick {
##################################################
    my ($prompt, $options, $default) = @_;    

    local($Log::Log4perl::caller_depth) += 1;

    my $default_int;
    my %files;

    if(@_ != 3 or ref($options) ne "ARRAY") {
        get_logger("")->logcroak("pick called with wrong #/type of args");
    }
    
    {
        my $count = 0;

        foreach (@$options) {
            print STDERR "[", ++$count, "] $_\n";
            $default_int = $count if $count eq $default;
            $files{$count} = $_;
        }
    
        print STDERR "$prompt [$default_int]> ";
        my $input = <STDIN>;
        chomp($input) if defined $input;

        $input = $default_int if !defined $input or !length($input);

        redo if $input !~ /^\d+$/ or 
                $input == 0 or 
                $input > scalar @$options;
        return "$files{$input}";
    }
}

=pod

=item C<ask($prompt, $default)>

Ask the user to either hit I<Enter> and select the displayed default
or to type in another string.

=cut

##################################################
sub ask {
##################################################
    my ($prompt, $default) = @_;    

    local($Log::Log4perl::caller_depth) += 1;

    if(@_ != 2) {
        get_logger("")->logcroak("ask() called with wrong # of args");
    }

    print STDERR "$prompt [$default]> ";
    my $value = <STDIN>;
    chomp $value;

    $value = $default if $value eq "";

    return $value;
}

=pod

=item C<mkd($dir)>

Create a directory of arbitrary depth, just like C<File::Path::mkpath>.

=cut

###############################################
sub mkd {
###############################################

    local($Log::Log4perl::caller_depth) += 1;

    _confirm "mkd @_" or return 1;

    INFO "mkpath @_";

    mkpath @_ or 
        get_logger("")->logcroak("Cannot mkdir @_ ($!)");
}

=pod

=item C<rmf($dir)>

Delete a directory and all of its descendents, just like C<rm -rf>
in the shell.

=cut

###############################################
sub rmf {
###############################################

    local($Log::Log4perl::caller_depth) += 1;

    _confirm "rmf $_[0]" or return 1;

    if(!-e $_[0]) {
        DEBUG "$_[0] doesn't exist - ignored";
        return;
    }

    INFO "rmtree @_";

    rmtree $_[0] or 
        get_logger("")->logcroak("Cannot rmtree $_[0] ($!)");
}

=pod

=item C<cd($dir)>

chdir to the given directory.

=cut

###############################################
sub cd {
###############################################

    local($Log::Log4perl::caller_depth) += 1;
    INFO "cd $_[0]";

    push @DIR_STACK, getcwd();
    chdir($_[0]) or 
        get_logger("")->logcroak("Cannot cd $_[0] ($!)");
}

=pod

=item C<cdback()>

chdir back to the last directory before a previous C<cd>.

=cut

###############################################
sub cdback {
###############################################

    local($Log::Log4perl::caller_depth) += 1;

    get_logger("")->logcroak("cd stack empty") unless @DIR_STACK;

    my $old_dir = pop @DIR_STACK;
    INFO "cdback to $old_dir";
    cd($old_dir);
}

=pod

=item C<make()>

Call C<make> in the shell.

=cut

###############################################
sub make {
###############################################

    local($Log::Log4perl::caller_depth) += 1;

    _confirm "make @_" or return 1;

    INFO "make @_";

    system("make @_") and 
        get_logger("")->logcroak("Cannot make @_ ($!)");
}

=pod

=cut

###############################################
sub check_zlib {
###############################################
    my($tar_file) = @_;

    if($tar_file =~ /\.tar\.gz\b|\.tgz\b/ and
       !Log::Log4perl::Util::module_available("IO::Zlib")) {

        get_logger("")->logcroak("$tar_file: Compressed tarballs can ",
               "only be processed with IO::Zlib installed.");
    }
}
     
#######################################
sub archive_sniff {
#######################################
    my($name) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    DEBUG "Sniffing archive '$name'";

    my ($dir) = ($name =~ /(.*?)\.(tar\.gz|tgz|tar)$/);
 
    return 0 unless defined $dir;

    $dir = basename($dir);
    DEBUG "dir=$dir";

    my $topdir;

    check_zlib($name);

    require Archive::Tar;
    my $tar = Archive::Tar->new($name);

    my @names = $tar->list_files(["name"]);

    get_logger("")->logcroak("Archive $name is empty") unless @names;

    (my $archdir = $names[0]) =~ s#/.*##;

    DEBUG "archdir=$archdir";

    for my $name (@names) {
        next if $name eq "./";
        $name =~ s#^\./##;
        ($topdir = $name) =~ s#/.*##;
        if($topdir ne $archdir) {
            return (0, $dir, $dir);
        }
    }

    DEBUG "Return $topdir $dir";

    return (1, $topdir, $dir);
}

=pod

=item C<pie($coderef, $filename, ...)>

Simulate "perl -pie 'do something' file". Edits files in-place. Expects
a reference to a subroutine as its first argument. It will read out the
file C<$filename> line by line and calls the subroutine setting
a localized C<$_> to the current line. The return value of the subroutine
will replace the previous value of the line.

Example:

    # Replace all 'foo's by 'bar' in test.dat
        pie(sub { s/foo/bar/g; $_; }, "test.dat");

Works with one or more file names.

=cut

###############################################
sub pie {
###############################################
    my($coderef, @files) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    for my $file (@files) {

        _confirm "editing $file in-place" or next;

        my $out = "";

        open FILE, "<$file" or 
            get_logger("")->logcroak("Cannot open $file ($!)");
        while(<FILE>) {
            $out .= $coderef->($_);
        }
        close FILE;

        blurt($out, $file);
    }
}

=pod

=item C<plough($coderef, $filename, ...)>

Simulate "perl -ne 'do something' file". Iterates over all lines
of all input files and calls the subroutine provided as the first argument. 

Example:

    # Print all lines containing 'foobar'
        plough(sub { print if /foobar/ }, "test.dat");

Works with one or more file names.

=cut

###############################################
sub plough {
###############################################
    my($coderef, @files) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    for my $file (@files) {

        _confirm "Ploughing through $file" or next;

        my $out = "";

        open FILE, "<$file" or 
            get_logger("")->logcroak("Cannot open $file ($!)");
        while(<FILE>) {
            $coderef->($_);
        }
        close FILE;
    }
}

=pod

=item C<my $data = slurp($file)>

Slurps in the file and returns a scalar with the file's content. If
called without argument, data is slurped from STDIN or from any files
provided on the command line (like E<lt>E<gt> operates).

=cut

###############################################
sub slurp {
###############################################
    my($file) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    my $from_file = defined($file);

    local $/ = undef;

    my $data;

    if($from_file) {
        INFO "Slurping data from $file";
        open FILE, "<$file" or 
            get_logger("")->logcroak("Cannot open $file ($!)");
        $data = <FILE>;
        close FILE;
        DEBUG "Read ", snip($data, $DATA_SNIPPED_LEN), " from $file";
    } else {
        INFO "Slurping data from <>";
        $data = <>;
        DEBUG "Read ", snip($data, $DATA_SNIPPED_LEN), " from <>";
    }

    return $data;
}

=pod

=item C<blurt($data, $file, $append)>

Opens a new file, prints the data in C<$data> to it and closes the file.
If C<$append> is set to a true value, data will be appended to the
file. Default is false, existing files will be overwritten.

=cut

###############################################
sub blurt {
###############################################
    my($data, $file, $append) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    _confirm(($append ? "Appending" : "Writing") . " " .
         length($data) . " bytes to $file") or return 1;

    open FILE, ">" . ($append ? ">" : "") . $file 
        or 
        get_logger("")->logcroak("Cannot open $file for writing ($!)");
    print FILE $data;
    close FILE;

    DEBUG "Wrote ", snip($data, $DATA_SNIPPED_LEN), " to $file";
}

=pod

=item C<($stdout, $stderr, $exit_code) = tap($cmd, @args)>

Run a command $cmd in the shell, and pass it @args as args.
Capture STDOUT and STDERR, and return them as strings. If
C<$exit_code> is 0, the command succeeded. If it is different,
the command failed and $exit_code holds its exit code.

Please note that C<tap()> is limited to single shell
commands, it won't work with output redirectors (C<ls E<gt>/tmp/foo>
2E<gt>&1).

In default mode, C<tap()> will concatenate the command and args
given and create a shell command line by redirecting STDERR to a temporary
file. C<tap("ls", "/tmp")>, for example, will result in

    'ls' '/tmp' 2>/tmp/sometempfile |

Note that all commands are protected by single quotes to make sure
arguments containing spaces are processed as singles, and no globbing
happens on wildcards. Arguments containing single quotes or backslashes
are escaped properly.

If quoting is undesirable, C<tap()> accepts an option hash as
its first parameter, 

    tap({no_quotes => 1}, "ls", "/tmp/*");

which will suppress any quoting:

    ls /tmp/* 2>/tmp/sometempfile |

Or, if you prefer double quotes, use

    tap({double_quotes => 1}, "ls", "/tmp/$VAR");

wrapping all args so that shell variables are interpolated properly:

    "ls" "/tmp/$VAR" 2>/tmp/sometempfile |

=cut

###############################################
sub tap {
###############################################
    my(@args) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    _confirm "tapping @args" or return 1;

    my $opts = {};

    $opts = shift @args if ref $args[0] eq "HASH";

    my $tmpfh   = File::Temp->new(UNLINK => 1, SUFFIX => '.dat');
    my $tmpfile = $tmpfh->filename();

    DEBUG "tempfile $tmpfile created";

    my $cmd;

    if($opts->{no_quotes}) {
        $cmd = join ' ', @args;
    } elsif($opts->{double_quotes}) {
        $cmd = join ' ', map { qquote($_, ":shell") } @args;
    } else {
            # Default mode: Single quotes
        $cmd = join ' ', map { quote($_) } @args;
    }
       
    $cmd = "$cmd 2>$tmpfile |";
    INFO "tapping $cmd";

    open PIPE, $cmd or 
        get_logger("")->logcroak("open $cmd | failed ($!)");
    my $stdout = join '', <PIPE>;
    close PIPE;

    my $exit_code = $?;

    my $stderr = slurp($tmpfile);

    return ($stdout, $stderr, $exit_code);
}

=pod

=item C<$quoted_string = qquote($string, [$metachars])>

Put a string in double quotes and escape all sensitive characters so
there's no unwanted interpolation. 
E.g., if you have something like

   print "foo!\n";

and want to put it into a double-quoted string, it will look like

    "print \"foo!\\n\""

Sometimes, not only backslashes and double quotes need to be escaped,
but also the target environment's meta chars. A string containing

    print "$<\n";

needs to have the '$' escaped like

    "print \"\$<\\n\";"

if you want to reuse it later in a shell context:

    $ perl -le "print \"\$<\\n\";"
    1212

C<qquote()> supports escaping these extra characters with its second,
optional argument, consisting of a string listing  all escapable characters:

    my $script  = 'print "$< rocks!\\n";';
    my $escaped = qquote($script, '!$'); # Escape for shell use
    system("perl -e $escaped");

    => 1212 rocks!

And there's a shortcut for shells: By specifying ':shell' as the
metacharacters string, qquote() will actually use '!$`'.

For example, if you wanted to run the perl code

    print "foobar\n";

via

    perl -e ...

on a box via ssh, you would use

    use Sysadm::Install qw(qquote);

    my $cmd = 'print "foobar!\n"';
       $cmd = "perl -e " . qquote($cmd, ':shell');
       $cmd = "ssh somehost " . qquote($cmd, ':shell');

    print "$cmd\n";
    system($cmd);

and get

    ssh somehost "perl -e \"print \\\"foobar\\\!\\\\n\\\"\""

which runs on C<somehost> without hickup and prints C<foobar!>.

Sysadm::Install comes with a script C<one-liner> (installed in bin),
which takes arbitrary perl code on STDIN and transforms it into
a one-liner:

    $ one-liner
    Type perl code, terminate by CTRL-D
    print "hello\n";
    print "world\n";
    ^D
    perl -e "print \"hello\\n\"; print \"world\\n\"; "

=cut

###############################################
sub qquote {
###############################################
    my($str, $metas) = @_;

    $str =~ s/([\\"])/\\$1/g;

    if(defined $metas) {
        $metas = '!$`' if $metas eq ":shell";
        $metas =~ s/\]/\\]/g;
        $str =~ s/([$metas])/\\$1/g;
    }

    return "\"$str\"";
}

=pod

=item C<$quoted_string = quote($string, [$metachars])>

Similar to C<qquote()>, just puts a string in single quotes.

=cut

###############################################
sub quote {
###############################################
    my($str, $metas) = @_;

    $str =~ s/([\\'])/\\$1/g;

    if(defined $metas) {
        $metas = '' if $metas eq ":shell";
        $metas =~ s/\]/\\]/g;
        $str =~ s/([$metas])/\\$1/g;
    }

    return "\'$str\'";
}

=pod

=item C<perm_cp($src, $dst, ...)>

Read the C<$src> file's user permissions and modify all
C<$dst> files to reflect the same permissions.

=cut

######################################
sub perm_cp {
######################################
    # Lifted from Ben Okopnik's
    # http://www.linuxgazette.com/issue87/misc/tips/cpmod.pl.txt

    local($Log::Log4perl::caller_depth) += 1;

    _confirm "perm_cp @_" or return 1;

    get_logger("")->logcroak("usage: perm_cp src dst ...") if @_ < 2;

    my $perms = perm_get($_[0]);
    perm_set($_[1], $perms);
}

=pod

=item C<$perms = perm_get($filename)>

Read the C<$filename>'s user permissions and owner/group. 
Returns an array ref to be
used later when calling C<perm_set($filename, $perms)>.

=cut 

######################################
sub perm_get {
######################################
    my($filename) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    my @stats = (stat $filename)[2,4,5] or
        
        get_logger("")->logcroak("Cannot stat $filename ($!)");

    INFO "perm_get $filename (@stats)";

    return \@stats;
}

=pod

=item C<perm_set($filename, $perms)>

Set file permissions and owner of C<$filename>
according to C<$perms>, which was previously
acquired by calling C<perm_get($filename)>.

=cut 

######################################
sub perm_set {
######################################
    my($filename, $perms) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    _confirm "perm_set $filename (@$perms)" or return 1;

    chown($perms->[1], $perms->[2], $filename) or 
        
        get_logger("")->logcroak("Cannot chown $filename ($!)");
    chmod($perms->[0] & 07777,    $filename) or
        
        get_logger("")->logcroak("Cannot chmod $filename ($!)");
}

=pod

=item C<sysrun($cmd)>

Run a shell command via C<system()> and die() if it fails. Also 
works with a list of arguments, which are then interpreted as program
name plus arguments, just like C<system()> does it.

=cut

######################################
sub sysrun {
######################################
    my(@cmds) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    _confirm "sysrun: @cmds" or return 1;

    get_logger("")->logcroak("usage: sysrun cmd ...") if @_ < 1;

    system(@cmds) and 
        get_logger("")->logcroak("@cmds failed ($!)");
}

=pod

=item C<hammer($cmd, $arg, ...)>

Run a command in the shell and simulate a user hammering the
ENTER key to accept defaults on prompts.

=cut

######################################
sub hammer {
######################################
    my(@cmds) = @_;

    require Expect;

    local($Log::Log4perl::caller_depth) += 1;

        _confirm "Hammer: @cmds" or return 1;

    my $exp = Expect->new();
    $exp->raw_pty(0);

    INFO "spawning: @cmds";
    $exp->spawn(@cmds);

    $exp->send_slow(0.1, "\n") for 1..199;
    $exp->expect(undef);
}

=pod

=item C<say($text, ...)>

Alias for C<print ..., "\n">, just like Perl6 is going to provide it.

=cut

######################################
sub say {
######################################
    print @_, "\n";
}

=pod

=item C<sudo_me()>

Check if the current script is running as root. If yes, continue. If not,
restart the current script with all command line arguments is restarted
under sudo:

    sudo scriptname args ...

Make sure to call this before any C<@ARGV>-modifying functions like
C<getopts()> have kicked in.

=cut

######################################
sub sudo_me {
######################################
    my($argv) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    _confirm "sudo_me" or return 1;

    $argv = \@ARGV unless $argv;

       # If we're not running as root, 
       # re-invoke the script via sudo
    if($> != 0) {
        DEBUG "Not running as root, calling sudo $0 @$argv";
        my $sudo = bin_find("sudo");
        get_logger("")->logcroak("Can't find sudo in PATH") unless $sudo;
        exec($sudo, $0, @$argv) or 
            get_logger("")->logcroak("exec failed!");
    }
}

=pod

=item C<bin_find($program)>

Search all directories in $PATH (the ENV variable) for an executable
named $program and return the full path of the first hit. Returns
C<undef> if the program can't be found.

=cut

######################################
sub bin_find {
######################################
    my($exe) = @_;

    for my $path (split /:/, $ENV{PATH}) {
        my $full = File::Spec->catfile($path, $exe);

        return $full if -x $full;
    }

    return undef;
}

=pod

=item C<fs_read_open($dir)>

Opens a file handle to read the output of the following process:

    cd $dir; find ./ -xdev -print0 | cpio -o0 |

This can be used to capture a file system structure. 

=cut

######################################
sub fs_read_open {
######################################
    my($dir) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    my $find = bin_find("find");
    get_logger("")->logcroak("Cannot find 'find'") unless defined $find;

    my $cpio = bin_find("cpio");
    get_logger("")->logcroak("Cannot find 'cpio'") unless defined $cpio;

    cd $dir;
 
    my $cmd = "$find . -xdev -print0 | $cpio -o0 --quiet 2>/dev/null ";

    DEBUG "Reading from $cmd";
    open my $in, "$cmd |" or 
        get_logger("")->logcroak("Cannot open $cmd");

    cdback;

    return $in;
}

=pod

=item C<fs_write_open($dir)>

Opens a file handle to write to a 

    | (cd $dir; cpio -i0)

process to restore a file system structure. To be used in conjunction
with I<fs_read_open>.

=cut

######################################
sub fs_write_open {
######################################
    my($dir) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    my $cpio = bin_find("cpio");
    get_logger("")->logcroak("Cannot find 'cpio'") unless defined $cpio;

    mkd $dir unless -d $dir;

    cd $dir;

    my $cmd = "$cpio -i0 --quiet";

    DEBUG "Writing to $cmd in dir $dir";
    open my $out, "| $cmd" or 
        get_logger("")->logcroak("Cannot open $cmd");

    cdback;

    return $out;
}

=pod

=item C<pipe_copy($in, $out, [$bufsize])>

Reads from $in and writes to $out, using sysread and syswrite. The
buffer size used defaults to 4096, but can be set explicitely.

=cut

######################################
sub pipe_copy {
######################################
    my($in, $out, $bufsize) = @_;

    local($Log::Log4perl::caller_depth) += 1;

    $bufsize ||= 4096;
    my $bytes = 0;

    INFO "Opening pipe (bufsize=$bufsize)";

    while(sysread($in, my $buf, $bufsize)) {
        $bytes += length $buf;
        syswrite $out, $buf;
    }

    INFO "Closed pipe (bufsize=$bufsize, transferred=$bytes)";
}

=pod

=item C<snip($data, $maxlen)>

Format the data string in C<$data> so that it's only (roughly) $maxlen
characters long and only contains printable characters.

If C<$data> contains unprintable character's they are replaced by 
"." (the dot). If C<$data> is longer than C<$maxlen>, it will be
formatted like

    (22)[abcdef[snip=11]stuvw]

indicating the length of the original string, the beginning, the
end, and the number of 'snipped' characters.

=cut

###########################################
sub snip {
###########################################
    my($data, $maxlen) = @_;

    if(length $data <= $maxlen) {
        return lenformat($data);
    }

    $maxlen = 12 if $maxlen < 12;
    my $sniplen = int(($maxlen - 8) / 2);

    my $start   = substr($data,  0, $sniplen);
    my $end     = substr($data, -$sniplen);
    my $snipped = length($data) - 2*$sniplen;

    return lenformat("$start\[snip=$snipped]$end", length $data);
}
    
###########################################
sub lenformat {
###########################################
    my($data, $orglen) = @_;

    return "(" . ($orglen || length($data)) . ")[" .
        printable($data) . "]";
}

###########################################
sub printable {
###########################################
    my($data) = @_;

    $data =~ s/[^ \w.;!?@#$%^&*()+\\|~`'-,><[\]{}="]/./g;
    return $data;
}

=pod

=back

=head1 AUTHOR

Mike Schilli, E<lt>m@perlmeister.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Mike Schilli

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut

1;
