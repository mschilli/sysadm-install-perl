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
use Cwd;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(cp rmf mkd cd make cdback download);

our $VERSION = '0.01';

our $OLD_DIR;

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
logging enabled? Then give shell programming, use Perl.

C<Sysadm::Install> executes shell-like commands performing typical
installation tasks: Copying files, extracting tarballs, calling C<make>.
It has a C<fail once and die> policy, meticulously checking the result
of ever operation and calling C<die()> immeditatly if anything fails.

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
    DEBUG "Copying $_[0] to $_[1]";
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
    DEBUG "Downloading $_[0] => ", basename($_[0]);
    getstore($_[0], basename($_[0])) or LOGDIE "Cannot download $_[0] ($!)";
}

=pod

=item C<untar($tgz_file)>

Untar the tarball in C<$tgz_file>, which typically adheres to the
C<someproject-X.XX.tgz> convention. But regardless of whether the 
archive actually contains a top directory C<someproject-X.XX>,
this function will behave if it had one. If it doesn't have one
a new directory is created before the unpacking takes place.

=cut

###############################################
sub untar {
###############################################
    DEBUG "Untarring $_[0]";
}

=pod

=item C<mkd($dir)>

Create a directory of arbitrary depth, just like C<File::Path::mkpath>.

=cut

###############################################
sub mkd {
###############################################
    DEBUG "Mkdir @_";
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
    DEBUG "rm -rf $_[0]";
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
    DEBUG "cd $_[0]";
    $OLD_DIR = getcwd();
    #DEBUG "old_dir=$OLD_DIR";
    chdir($_[0]) or LOGDIE("Cannot cd $_[0] ($!)");
    #DEBUG "new_dir=", getcwd();
}

=pod

=item C<cdback()>

chdir back to the last directory before a previous C<cd>.

=cut

###############################################
sub cdback {
###############################################
    DEBUG "cdback to $OLD_DIR";
    cd($OLD_DIR);
}

=pod

=item C<make()>

Call C<make> in the shell.

=cut

###############################################
sub make {
###############################################
    DEBUG "make @_";
    system("make @_") and LOGDIE "Cannot make @_ ($!)";
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
