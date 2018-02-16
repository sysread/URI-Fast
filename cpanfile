requires 'URI::Split';
requires 'URI::Encode::XS';
requires 'Exporter';
requires 'common::sense';

on test => sub {
  requires 'Test2::Bundle::Extended' => 0;
  requires 'Test::Pod' => 1.41;
};
