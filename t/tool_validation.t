use Mojo::Base -strict, -signatures;

use Test::More;
use MCP::Tool;
use Mojo::JSON qw(false);

subtest 'Default input schema' => sub {
  my $tool = MCP::Tool->new;

  is $tool->validate_input({}),    0, 'empty object is valid';
  is $tool->validate_input(undef), 1, 'undefined arguments are invalid';
};

subtest 'Required properties' => sub {
  my $tool = MCP::Tool->new(
    input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']});

  is $tool->validate_input({msg => 'hello'}), 0, 'required string is valid';
  is $tool->validate_input({}),               1, 'missing required property is invalid';
  is $tool->validate_input({msg => 23}),      1, 'wrong property type is invalid';
};

subtest 'Additional properties' => sub {
  my $tool = MCP::Tool->new(
    input_schema => {type => 'object', properties => {msg => {type => 'string'}}, additionalProperties => false});

  is $tool->validate_input({msg => 'hello'}),             0, 'known property is valid';
  is $tool->validate_input({msg => 'hello', extra => 1}), 1, 'unknown property is invalid';
};

done_testing;
