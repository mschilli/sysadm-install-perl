###############################################
package Sysadm::Install;
###############################################

use 5.006;
use strict;
use warnings;

use File::Copy;
use File::Path;
use Log::Log4perl qw(:easy);
use LWP::Simple;
use File::Basename;
use Archive::Tar;
use Cwd;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(cp rmf mkd cd make cdback download untar);

our $VERSION = '0.01';

our @DIR_STACK;

=pod

=head1 NAME

Sysadm::Install - Typical installation tasks for system administrators

=head1 SYNOPSIS

  use Sysadm::Install;

  my $INST_DIR = '/home/me/install/';

  cd($INST_DIR);
  cp("/deliver/someproj.tgz", ".");
  untar("someproj.tgz");
  cd("someproj");
  make("test install");

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

=cut

###############################################
sub cp {
###############################################
    INFO "cp $_[0] $_[1]";
    File::Copy::copy @_ or LOGDIE "Cannot copy $_[0] to $_[1] ($!)";
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
a new directory is created before the unpacking takes place.

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
        rmf($topdir);
        mkd($topdir);
        cd($topdir);
        $arch->extract();
        cdback();
    }

    return $topdir;
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

=back

=cut

#######################################
sub archive_sniff {
#######################################
    my($name) = @_;

    DEBUG "Sniffing archive '$name'";

    my ($dir) = ($name =~ /(.*?)\.(tar\.gz|tgz)$/);
 
    return 0 unless defined $dir;

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

=head1 AUTHOR

Mike Schilli, E<lt>m@perlmeister.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Mike Schilli

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut

1;
