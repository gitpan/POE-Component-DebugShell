# $Id: Makefile.PL 224 2004-04-24 20:44:16Z sungo $
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME => 'POE::Component::DebugShell',
    AUTHOR => 'Matt Cashner (sungo@pobox.com)',
    VERSION_FROM => 'lib/POE/Component/DebugShell.pm',
    PREREQ_PM => {
        'POE' => '0.2601',
        'POE::API::Peek' => '0.02',
        'Test::More' => 0,
    },
    dist => {
        PREOP => 'svn log > ${DISTVNAME}/Changes',
    },

);

