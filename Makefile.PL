use ExtUtils::MakeMaker;
WriteMakefile(
    NAME		=> 'BackupD',
    VERSION_FROM	=> 'bin/BackupD.pl',
    EXE_FILES		=> [ 'bin/BackupD.pl' ],
    PREREQ_PM		=> {},
    dist                => {
        COMPRESS => 'gzip --force --best'
    },
);
