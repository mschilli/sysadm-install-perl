###############################################
package Sysadm::Install;
###############################################

use 5.006;
use strict;
use warnings;

our $VERSION = '0.15';

use File::Copy;
use File::Path;
use Log::Log4perl qw(:easy);
use LWP::Simple;
use File::Basename;
use File::Spec::Functions qw(rel2abs abs2rel);
use Archive::Tar;
use Cwd;
use File::Temp;

our $DRY_RUN;
our $DRY_RUN_MSG;

dry_run(0);

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

our @EXPORTABLE = qw(
cp rmf mkd cd make 
cdback download untar 
pie slurp blurt mv tap 
plough qquote quote perm_cp
sysrun untar_in pick ask
hammer say
sudo_me bin_find
fs_read_open fs_write_open pipe_copy
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
        die __PACKAGE__ . 
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
    INFO "cp $_[0] $_[1] $DRY_RUN_MSG";
    return 1 if $DRY_RUN;
    File::Copy::copy @_ or LOGDIE "Cannot copy $_[0] to $_[1] ($!)";
}

=pod

=item C<mv($source, $target)>

Move a file from C<$source> to C<$target>. C<target> can be a directory.

=cut

###############################################
sub mv {
###############################################
    INFO "mv $_[0] $_[1] $DRY_RUN_MSG";
    return 1 if $DRY_RUN;
    File::Copy::move @_ or LOGDIE "Cannot move $_[0] to $_[1] ($!)";
}

=pod

=item C<download($url)>

Download a file specified by C<$url> and store it under the
name returned by C<basename($url)>.

=cut

###############################################
sub download {
###############################################
    INFO "Downloading $_[0] => ", basename($_[0]), " $DRY_RUN_MSG";
    return 1 if $DRY_RUN;
    getstore($_[0], basename($_[0])) or LOGDIE "Cannot download $_[0] ($!)";
}

=pod

=item C<untar($tgz_file)>

Untar the tarball in C<$tgz_file>, which typically adheres to the
C<someproject-X.XX.tgz> convention. But regardless of whether the 
archive actually contains a top directory C<someproject-X.XX>,
this function will behave if it had one. If it doesn't have one,
a new directory is created before the unpacking takes place. Unpacks
the tarball into the current directory, no matter where the tarfile
is located.

=cut

###############################################
sub untar {
###############################################
    die "untar called without defined tarfile" unless @_ == 1 
         and defined $_[0];

    INFO "untar $_[0] $DRY_RUN_MSG";
    return 1 if $DRY_RUN;

    my($nice, $topdir, $namedir) = archive_sniff($_[0]);

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
        rename $topdir, $namedir or die "Can't rename $topdir, $namedir";
    } else {
        die "no topdir" unless defined $topdir;
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

    LOGDIE "not enough arguments" if
      ! defined $tar_file or ! defined $dir;

    INFO "Untarring $tar_file in $dir $DRY_RUN_MSG";
    return 1 if $DRY_RUN;

    mkd($dir) unless -d $dir;

    my $tar_file_abs = rel2abs($tar_file, dirname($tar_file));

    cd($dir);
    my $arch = Archive::Tar->new("$tar_file_abs");
    $arch->extract() or LOGDIE "Extract failed: $!";
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

    my $default_int;
    my %files;

    if(@_ != 3 or ref($options) ne "ARRAY") {
        die "pick called with wrong #/type of args";
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

    if(@_ != 2) {
        die "ask() called with wrong # of args";
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
    INFO "mkd @_ $DRY_RUN_MSG";
    return 1 if $DRY_RUN;
    mkpath @_ or LOGDIE "Cannot mkdir @_ ($!)";
}

=pod

=item C<rmf($dir)>

Delete a directory and all of its descendents, just like C<rm -rf>
in the shell.

=cut

###############################################
sub rmf {
###############################################
    INFO "rmf $_[0] $DRY_RUN_MSG";
    return 1 if $DRY_RUN;

    if(!-e $_[0]) {
        DEBUG "$_[0] doesn't exist - ignored";
        return;
    }
    rmtree $_[0] or LOGDIE "Cannot rmtree $_[0] ($!)";
}

=pod

=item C<cd($dir)>

chdir to the given directory.

=cut

###############################################
sub cd {
###############################################
    INFO "cd $_[0]";

    push @DIR_STACK, getcwd();
    chdir($_[0]) or LOGDIE("Cannot cd $_[0] ($!)");
}

=pod

=item C<cdback()>

chdir back to the last directory before a previous C<cd>.

=cut

###############################################
sub cdback {
###############################################
    die "cd stack empty" unless @DIR_STACK;

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
    INFO "make @_ $DRY_RUN_MSG";
    return 1 if $DRY_RUN;

    system("make @_") and LOGDIE "Cannot make @_ ($!)";
}

=pod

=cut

#######################################
sub archive_sniff {
#######################################
    my($name) = @_;

    DEBUG "Sniffing archive '$name'";

    my ($dir) = ($name =~ /(.*?)\.(tar\.gz|tgz|tar)$/);
 
    return 0 unless defined $dir;

    $dir = basename($dir);
    DEBUG "dir=$dir";

    my $topdir;

    my $tar = Archive::Tar->new($name);

    my @names = $tar->list_files(["name"]);

    die "Archive $name is empty" unless @names;

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

    for my $file (@files) {

        INFO "editing $file in-place $DRY_RUN_MSG";
        next if $DRY_RUN;

        my $out = "";

        open FILE, "<$file" or LOGDIE "Cannot open $file ($!)";
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

    for my $file (@files) {

        INFO "Ploughing through $file $DRY_RUN_MSG";
        next if $DRY_RUN;

        my $out = "";

        open FILE, "<$file" or LOGDIE "Cannot open $file ($!)";
        while(<FILE>) {
            $coderef->($_);
        }
        close FILE;
    }
}

=pod

=item C<my $data = slurp($file)>

Slurps in the file and returns a scalar with the file's content.

=cut

###############################################
sub slurp {
###############################################
    my($file) = @_;

    INFO "slurping data from $file";

    local $/ = undef;

    open FILE, "<$file" or LOGDIE "Cannot open $file ($!)";
    my $data = <FILE>;
    close FILE;

    DEBUG "Read ", length($data), " bytes from $file";

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

    INFO(($append ? "appending" : "writing") . " " .
         length($data) . " bytes to $file $DRY_RUN_MSG");
    return 1 if $DRY_RUN;

    open FILE, ">" . ($append ? ">" : "") . $file 
        or LOGDIE "Cannot open $file for writing ($!)";
    print FILE $data;
    close FILE;
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

    if($DRY_RUN) {
        INFO "tapping @args $DRY_RUN_MSG";
        return 1;
    }

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

    open PIPE, $cmd or LOGDIE "open $cmd | failed ($!)";
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

    INFO "perm_cp @_ $DRY_RUN_MSG";
    return 1 if $DRY_RUN;

    LOGDIE("usage: perm_cp src dst ...") if @_ < 2;

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

    my @stats = (stat $filename)[2,4,5] or
        LOGDIE "Cannot stat $filename ($!)";

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

    INFO "perm_set $filename (@$perms) $DRY_RUN_MSG";
    return 1 if $DRY_RUN;

    chown($perms->[1], $perms->[2], $filename) or 
        LOGDIE "Cannot chown $filename ($!)";
    chmod($perms->[0] & 07777,    $filename) or
        LOGDIE "Cannot chmod $filename ($!)";
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

    INFO "sysrun: @cmds $DRY_RUN_MSG";
    return 1 if $DRY_RUN;

    LOGDIE("usage: sysrun cmd ...") if @_ < 1;

    system(@cmds) and LOGDIE "@cmds failed ($!)";
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

    if($DRY_RUN) {
        INFO "Hammer: @cmds $DRY_RUN_MSG";
        return 1 if $DRY_RUN;
    }

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

    if($DRY_RUN) {
        INFO "sudo_me $DRY_RUN_MSG";
        return 1;
    }

    $argv = \@ARGV unless $argv;

       # If we're not running as root, 
       # re-invoke the script via sudo
    if($> != 0) {
        DEBUG "Not running as root, calling sudo $0 @$argv";
        my $sudo = bin_find("sudo");
        LOGDIE "Can't find sudo in PATH" unless $sudo;
        exec($sudo, $0, @$argv) or LOGDIE "exec failed!";
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

    my $find = bin_find("find");
    LOGDIE "Cannot find 'find'" unless defined $find;

    my $cpio = bin_find("cpio");
    LOGDIE "Cannot find 'cpio'" unless defined $cpio;

    cd $dir;
 
    my $cmd = "$find . -xdev -print0 | $cpio -o0 --quiet 2>/dev/null ";

    DEBUG "Reading from $cmd";
    open my $in, "$cmd |" or LOGDIE "Cannot open $cmd";

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

    my $cpio = bin_find("cpio");
    LOGDIE "Cannot find 'cpio'" unless defined $cpio;

    mkd $dir unless -d $dir;

    cd $dir;

    my $cmd = "$cpio -i0 --quiet";

    DEBUG "Writing to $cmd in dir $dir";
    open my $out, "| $cmd" or LOGDIE "Cannot open $cmd";

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
