# $Id: Makefile.PL,v 1.2 2004/02/20 03:30:51 sungo Exp $
use inc::Module::Install;

name            ('POE-Component-DebugShell');
author          ('Matt Cashner (cpan@eekeek.org)');
version_from    ('lib/POE/Component/DebugShell.pm');
license         ('bsd');

requires        ('perl' => '5.006001');
requires        ('POE' => '0.2601');
requires        ('POE::API::Peek' => '0.02');

build_requires  ('Test::More');
build_requires  ('Module::Signature');

no_index        ('directory' => 'examples');

auto_include    ();
auto_install    ();

&WriteAll;
