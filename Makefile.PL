use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Sysadm::Install',
    VERSION_FROM      => 'lib/Sysadm/Install.pm', # finds $VERSION
    PREREQ_PM         => {
        Expect          => undef,
        Log::Log4perl   => undef,
        File::Copy      => undef,
        File::Path      => undef,
        File::Basename  => undef,
        Archive::Tar    => undef,
        LWP::Simple     => undef,
        Cwd             => undef,
        File::Temp      => undef,
                         }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Sysadm/Install.pm', # retrieve abstract from module
       AUTHOR         => 'Mike Schilli <m@perlmeister.com>') : ()),
);
