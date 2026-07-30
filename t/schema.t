use Mojo::Base -strict, -signatures;

use Test::More;
use MCP::Tool;
use Mojo::JSON qw(false true);

subtest 'Default dialect is JSON Schema 2020-12' => sub {
  my $tool
    = MCP::Tool->new(
    input_schema => {type => 'object', properties => {pair => {type => 'array', prefixItems => [{type => 'integer'}]}}}
    );

  is $tool->validate_input({pair => [23, 'whatever']}), 0, 'prefixItems satisfied';
  is $tool->validate_input({pair => ['nope']}),         1, 'prefixItems violated';

  my $dependent = MCP::Tool->new(input_schema => {type => 'object', dependentRequired => {a => ['b']}});
  is $dependent->validate_input({a => 1, b => 2}), 0, 'dependentRequired satisfied';
  is $dependent->validate_input({a => 1}),         1, 'dependentRequired violated';
};

subtest 'Explicit dialect' => sub {
  my $tool = MCP::Tool->new(
    input_schema => {
      '$schema'  => 'http://json-schema.org/draft-07/schema#',
      type       => 'object',
      properties => {pair => {type => 'array', prefixItems => [{type => 'integer'}]}}
    }
  );

  is $tool->validate_input({pair => ['nope']}), 0, 'prefixItems is not a draft-07 keyword';
};

subtest 'Unsupported dialect' => sub {
  my $tool = MCP::Tool->new(input_schema => {'$schema' => 'https://json-schema.org/draft/2077-01/schema'});

  eval { $tool->validate_input({}) };
  like $@, qr/Unsupported JSON Schema dialect/, 'unsupported dialect';
};

subtest 'References' => sub {
  my $local = MCP::Tool->new(input_schema =>
      {type => 'object', properties => {msg => {'$ref' => '#/$defs/text'}}, '$defs' => {text => {type => 'string'}}});
  is $local->validate_input({msg => 'hello'}), 0, 'local reference resolved';
  is $local->validate_input({msg => 23}),      1, 'local reference enforced';

  my $remote = MCP::Tool->new(
    input_schema => {type => 'object', properties => {msg => {'$ref' => 'https://example.com/schema.json'}}});
  is $remote->validate_input({msg => 'hello'}), 1, 'network reference is not dereferenced';
};

subtest 'Composition depth' => sub {
  my $tool = MCP::Tool->new(
    max_schema_depth => 3,
    input_schema     => {allOf => [{allOf => [{allOf => [{allOf => [{type => 'object'}]}]}]}]}
  );

  is $tool->validate_input({}), 1, 'schema nested too deeply';
};

subtest 'Output validation' => sub {
  my $tool = MCP::Tool->new(
    output_schema => {type => 'object', properties => {count => {type => 'integer'}}, required => ['count']});

  is $tool->validate_output({count => 23}),  0, 'structured content is valid';
  is $tool->validate_output({count => 'x'}), 1, 'structured content is invalid';

  my $result = $tool->structured_result({count => 23});
  is $result->{isError}, false, 'not an error';
  is_deeply $result->{structuredContent}, {count => 23}, 'structured content';

  my $invalid = $tool->structured_result({count => 'x'});
  is $invalid->{isError},           true,                                                  'is an error';
  is $invalid->{structuredContent}, undef,                                                 'no structured content';
  is $invalid->{content}[0]{text},  'Structured content does not match the output schema', 'error message';

  my $schemaless = MCP::Tool->new;
  is $schemaless->validate_output({whatever => 1}), 0, 'no output schema';
};

done_testing;
