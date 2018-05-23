package UriFastMakeMaker;

use strict;
use warnings;
use lib 'inc';
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME             => 'URI::Fast',
  AUTHOR           => 'Jeff Ober <sysread@fastmail.fm>',
  VERSION_FROM     => "lib/URI/Fast.pm",
  ABSTRACT_FROM    => 'README.pod',
  LICENSE          => 'perl_5',
  MIN_PERL_VERSION => '5.010',
  PREREQ_PRINT     => 1,

  META_MERGE => {
    'meta-spec' => {
      version => 2,
    },

    resources => {
      homepage => "https://github.com/sysread/URI-Fast",

      bugtracker => {
        web => "https://github.com/sysread/URI-Fast/issues"
      },

      repository => {
        type => "git",
        url  => "https://github.com/sysread/URI-Fast.git",
        web  => "https://github.com/sysread/URI-Fast"
      }
    },
  },

  MAN3PODS => {
    'README.pod' => "blib/man3/URI::Fast.3",
  },

  test => {
    TESTS => 't/*',
  },

  clean => {
    FILES => "*.bak URI-Fast-*.tar.gz",
  },

  BUILD_REQUIRES => {
    'ExtUtils::MakeMaker' => '6.63_03',
  },

  TEST_REQUIRES => {
    'Test2'           => '1.302125',
    'Test2::Suite'    => '0.000100',
    'Test2::V0'       => 0,
    'Test::LeakTrace' => '0.16',
    'Test::Pod'       => 1.41,
    'URI::Split'      => 0,
    'URI::Encode::XS' => '0.11',
  },

  PREREQ_PM => {
    'Carp'     => 0,
    'Exporter' => 0,
    'parent'   => 0,
  },
);

1;
