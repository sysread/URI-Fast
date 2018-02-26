requires 'perl', '5.010';

requires 'Exporter';
requires 'Inline::C';
requires 'URI::Encode::XS', '0.07';

on test => sub {
  requires 'Test2::Bundle::Extended' => 0;
  requires 'Test::Pod' => 1.41;
  requires 'URI::Split' => 0,
};
