requires 'perl'     => '5.010';
requires 'Carp'     => '0';
requires 'Exporter' => '0';
requires 'parent'   => '0';

on build => sub {
  requires 'ExtUtils::MakeMaker' => '6.63_03';
};

on test => sub {
  requires 'ExtUtils::testlib' => '0';
  requires 'Test2'             => '1.302125';
  requires 'Test2::Suite'      => '0.000100';
  requires 'Test2::V0'         => '0';
  requires 'Test::LeakTrace'   => '0.16';
  requires 'Test::Pod'         => '1.41';
  requires 'URI::Encode::XS'   => '0.11';
  requires 'URI::Split'        => '0';
};
