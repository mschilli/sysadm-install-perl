use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

eval {
    require Expect;
};

if($@) {
    print <<EOT;
WARNING: Expect not found.
         You won't be able to use hammer().
         Install Expect from CPAN later if you want to.
EOT
}

WriteMakefile(
    NAME              => 'Sysadm::Install',
    VERSION_FROM      => 'lib/Sysadm/Install.pm', # finds $VERSION
    EXE_FILES         => ['eg/one-liner'],
    PREREQ_PM         => {
        Log::Log4perl   => 0.48,
        File::Copy      => 0,
        File::Path      => 0,
        File::Basename  => 0,
        Archive::Tar    => 1.23,
        LWP::Simple     => 0,
        Cwd             => 0,
        File::Temp      => 0,
                         }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Sysadm/Install.pm', # retrieve abstract from module
       AUTHOR         => 'Mike Schilli <m@perlmeister.com>') : ()),
);
