###############################################
package Sysadm::Install;
###############################################

use 5.006;
use strict;
use warnings;

our $VERSION = '0.08';

use File::Copy;
use File::Path;
use Log::Log4perl qw(:easy);
use LWP::Simple;
use File::Basename;
use File::Spec::Functions qw(rel2abs abs2rel);
use Archive::Tar;
use Cwd;
use File::Temp;

our @EXPORTABLE = qw(
cp rmf mkd cd make 
cdback download untar 
pie slurp blurt mv tap 
plough qquote perm_cp
sysrun untar_in pick ask
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
  my($stdout, $stderr) = tap("ls -R");

=head1 DESCRIPTION

Have you ever wished for your installation shell scripts to run
reproducably, without much programming fuzz, and even with optional
logging enabled? Then give up shell programming, use Perl.

C<Sysadm::Install> executes shell-like commands performing typical
installation tasks: Copying files, extracting tarballs, calling C<make>.
It has a C<fail once and die> policy, meticulously checking the result
of every operation and calling C<die()> immeditatly if anything fails.

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
    INFO "cp $_[0] $_[1]";
    File::Copy::copy @_ or LOGDIE "Cannot copy $_[0] to $_[1] ($!)";
}

=pod

=item C<mv($source, $target)>

Move a file from C<$source> to C<$target>. C<target> can be a directory.

=cut

###############################################
sub mv {
###############################################
    INFO "mv $_[0] $_[1]";
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
    INFO "Downloading $_[0] => ", basename($_[0]);
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

    INFO "untar $_[0]";

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

    mkd($dir) unless -d $dir;

    my $tar_file_abs = rel2abs($tar_file, dirname($tar_file));

    cd($dir);
    INFO "Untarring $tar_file_abs in $dir";
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
        die "Pick::list called with wrong #/type of args";
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
        chomp($input);

        $input = $default_int unless length($input);

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
    INFO "mkd @_";
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
    INFO "rmf $_[0]";
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
    INFO "make @_";
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

        INFO "editing $file in-place";

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

        INFO "Ploughing through $file";

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

    INFO(($append ? "appending" : "writing") . " data to $file");

    open FILE, ">" . ($append ? ">" : "") . $file 
        or LOGDIE "Cannot open $file for writing ($!)";
    print FILE $data;
    close FILE;
}

=pod

=item C<($stdout, $stderr) = tap($cmd)>

Rund a command C<$cmd> in the shell, capture STDOUT and STDERR, and
return them as strings.

=cut

###############################################
sub tap {
###############################################
    my($cmd) = @_;

    my $tmpfh   = File::Temp->new(UNLINK => 1, SUFFIX => '.dat');
    my $tmpfile = $tmpfh->filename();

    DEBUG "tempfile $tmpfile created";

    $cmd = "$cmd 2>$tmpfile |";
    INFO "tap $cmd";

    open PIPE, $cmd or LOGDIE "open $cmd | failed ($!)";
    my $stdout = join '', <PIPE>;
    close PIPE or LOGDIE "close $cmd failed ($!)";

    my $stderr = slurp($tmpfile);

    return ($stdout, $stderr);
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
metacharacters string, qquote() will actually use '!$[]()+?'.

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

=cut

###############################################
sub qquote {
###############################################
    my($str, $metas) = @_;

    $str =~ s/([\\"])/\\$1/g;

    if(defined $metas) {
        $metas = '!$[]()+?' if $metas eq ":shell";
        $metas =~ s/\]/\\]/g;
        $str =~ s/([$metas])/\\$1/g;
    }

    return "\"$str\"";
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

    LOGDIE("usage: perm_cp src dst ...") if @_ < 2;

    my @perms = (stat shift)[2,4,5];
    chown @perms[1,2],          @_;
    chmod $perms[0] & 07777,    @_;
}

=pod

=item C<sysrun($cmd)>

Run a shell command via C<system()> and die() if it fails.

=cut

######################################
sub sysrun {
######################################
    my(@cmds) = @_;

    LOGDIE("usage: sysrun cmd ...") if @_ < 1;

    INFO "sysrun: @cmds";

    system(@cmds) and LOGDIE "@cmds failed ($!)";
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
