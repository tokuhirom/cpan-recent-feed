use inc::Module::Install;
name 'App-cpanrecentfeed';
all_from 'lib/App/cpanrecentfeed.pm';

requires 'JSON';
requires 'Time::Piece';
requires 'Archive::Tar';
requires 'Algorithm::Diff';
requires 'HTML::TreeBuilder::XPath';
requires 'XML::Feed';
requires 'DateTime';
requires 'Getopt::Long';
requires 'Pod::Usage';
requires 'URI::Fetch';
requires 'Cache::File';

tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
test_requires 'Test::More';
test_requires 'YAML';
author_tests 'xt';
use_test_base;
auto_include;
WriteAll;
