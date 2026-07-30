package MCP::Tool;
use Mojo::Base 'MCP::Primitive', -signatures;

use Carp qw(croak);
use JSON::Schema::Tiny;
use Mojo::JSON   qw(false to_json true);
use Mojo::Util   qw(b64_encode);
use Scalar::Util qw(blessed);

use constant DIALECTS => {
  'http://json-schema.org/draft-07/schema#'      => 'draft7',
  'https://json-schema.org/draft/2019-09/schema' => 'draft2019-09',
  'https://json-schema.org/draft/2020-12/schema' => 'draft2020-12'
};

has annotations      => sub { {} };
has code             => sub { die 'Tool code not implemented' };
has description      => 'Generic MCP tool';
has input_schema     => sub { {type => 'object'} };
has max_schema_depth => 50;
has name             => 'tool';
has 'output_schema';

sub audio_result ($self, $audio, $options = {}, $is_error = 0) {
  return {
    content => [{type => 'audio', data => b64_encode($audio, ''), mimeType => $options->{mime_type} // 'audio/wav'}],
    isError => $is_error ? true : false
  };
}

sub call ($self, $args, $context) {
  local $self->{context} = $context;
  my $result = $self->code->($self, $args);
  return $result->then(sub { $self->_type_check($_[0]) }) if blessed($result) && $result->isa('Mojo::Promise');
  return $self->_type_check($result);
}

sub header_params ($self) { return $self->{header_params} //= _header_params($self->input_schema) }

sub image_result ($self, $image, $options = {}, $is_error = 0) {
  return {
    content => [{
      type        => 'image',
      data        => b64_encode($image, ''),
      mimeType    => $options->{mime_type}   // 'image/png',
      annotations => $options->{annotations} // {}
    }],
    isError => $is_error ? true : false
  };
}

sub resource_link_result ($self, $uri, $options = {}, $is_error = 0) {
  return {
    content => [{
      type        => 'resource_link',
      uri         => $uri,
      name        => $options->{name}        // '',
      description => $options->{description} // '',
      mimeType    => $options->{mime_type}   // 'text/plain',
      annotations => $options->{annotations} // {}
    }],
    isError => $is_error ? true : false
  };
}

sub structured_result ($self, $data, $is_error = 0) {
  return $self->text_result('Structured content does not match the output schema', 1) if $self->validate_output($data);
  my $result = $self->text_result(to_json($data), $is_error);
  $result->{structuredContent} = $data;
  return $result;
}

sub text_result ($self, $text, $is_error = 0) {
  return {content => [{type => 'text', text => "$text"}], isError => $is_error ? true : false};
}

sub validate_input ($self, $args) {
  my $schema    = $self->input_schema;
  my $validator = $self->{input_validator} //= $self->_validator($schema);
  return $validator->evaluate($args, $schema) ? 0 : 1;
}

sub validate_output ($self, $data) {
  return 0 unless my $schema = $self->output_schema;
  my $validator = $self->{output_validator} //= $self->_validator($schema);
  return $validator->evaluate($data, $schema) ? 0 : 1;
}

sub _header_params ($schema, $path = []) {
  return [] unless ref $schema eq 'HASH' && ref(my $properties = $schema->{properties}) eq 'HASH';

  my @params;
  for my $key (sort keys %$properties) {
    next unless ref(my $property = $properties->{$key}) eq 'HASH';
    my @next = (@$path, $key);
    push @params, {name => $property->{'x-mcp-header'}, path => \@next, type => $property->{type} // ''}
      if defined $property->{'x-mcp-header'};
    push @params, @{_header_params($property, \@next)};
  }

  return \@params;
}

sub _type_check ($self, $result) {
  return $result if ref $result eq 'HASH' && (exists $result->{content} || exists $result->{resultType});
  return $self->text_result($result);
}

sub _validator ($self, $schema) {
  my %options = (boolean_result => 1, max_depth => $self->max_schema_depth);
  if (my $dialect = ref $schema eq 'HASH' ? $schema->{'$schema'} : undef) {
    croak qq{Unsupported JSON Schema dialect "$dialect"} unless DIALECTS->{$dialect};
  }
  else { $options{specification_version} = 'draft2020-12' }
  return JSON::Schema::Tiny->new(%options);
}

1;

=encoding utf8

=head1 NAME

MCP::Tool - Tool container

=head1 SYNOPSIS

  use MCP::Tool;

  my $tool = MCP::Tool->new;

=head1 DESCRIPTION

L<MCP::Tool> is a container for tools to be called. Arguments and structured content are validated with
L<JSON::Schema::Tiny>, which covers JSON Schema 2020-12, 2019-09, and draft-07, but only partially implements
C<$id>, C<$dynamicRef>, and C<$dynamicAnchor>.

=head1 ATTRIBUTES

L<MCP::Tool> implements the following attributes.

=head2 annotations

  my $annotations = $tool->annotations;
  $tool           = $tool->annotations({title => '...'});

Optional annotations for the tool which provide additional metadata about the tool behavior.

=head2 code

  my $code = $tool->code;
  $tool    = $tool->code(sub { ... });

Tool code.

=head2 description

  my $description = $tool->description;
  $tool           = $tool->description('A brief description of the tool');

Description of the tool.

=head2 input_schema

  my $schema = $tool->input_schema;
  $tool      = $tool->input_schema({type => 'object', properties => {foo => {type => 'string'}}});

JSON schema for validating input arguments. Schemas without a C<$schema> keyword are interpreted as JSON Schema
2020-12, the default dialect of the Model Context Protocol; schemas with one are interpreted as the dialect it
names, which has to be one of 2020-12, 2019-09, or draft-07. Any other dialect is an error.

Properties may carry an C<x-mcp-header> keyword, naming the HTTP header a client has to mirror the argument in, for
the benefit of gateways that route on headers alone. See L</"header_params">.

=head2 max_schema_depth

  my $depth = $tool->max_schema_depth;
  $tool     = $tool->max_schema_depth(10);

How many levels deep validation may descend into a schema before it is aborted, which bounds the work a deeply
nested or recursive schema can cause. Defaults to C<50>.

=head2 name

  my $name = $tool->name;
  $tool    = $tool->name('my_tool');

Name of the tool.

=head2 output_schema

  my $schema = $tool->output_schema;
  $tool      = $tool->output_schema({type => 'object', properties => {foo => {type => 'string'}}});

JSON schema for validating output results, interpreted with the same dialect rules as L</"input_schema">.

=head1 METHODS

L<MCP::Tool> inherits all methods from L<MCP::Primitive> and implements the following new ones.

=head2 audio_result

  my $result = $tool->audio_result($bytes, $options, $is_error);

Returns an audio result in the expected format, optionally marking it as an error.

These options are currently available:

=over 2

=item mime_type

  mime_type => 'audio/wav'

Specifies the MIME type of the audio, defaults to C<audio/wav>.

=back

=head2 call

  my $result = $tool->call($args, $context);

Calls the tool with the given arguments and context, returning a result. The result can be a promise or a direct value.

=head2 header_params

  my $params = $tool->header_params;

All properties of L</"input_schema"> annotated with C<x-mcp-header>, as an array reference of hash references with
C<name>, C<path> and C<type> keys. Only properties reachable from the schema root through a chain of C<properties>
keys are considered, since the protocol forbids C<x-mcp-header> anywhere else. The result is cached after the first
call.

=head2 image_result

  my $result = $tool->image_result($bytes, $options, $is_error);

Returns an image result in the expected format, optionally marking it as an error.

These options are currently available:

=over 2

=item annotations

  annotations => {audience => ['user']}

Annotations for the image.

=item mime_type

  mime_type => 'image/png'

Specifies the MIME type of the image, defaults to C<image/png>.

=back

=head2 resource_link_result

  my $result = $tool->resource_link_result($uri, $options, $is_error);

Returns a resource link result in the expected format, optionally marking it as an error.

These options are currently available:

=over 2

=item annotations

  annotations => {audience => ['user']}

Annotations for the resource link.

=item description

  description => 'A brief description of the resource'

Description of the resource.

=item mime_type

  mime_type => 'text/x-perl'

Specifies the MIME type of the resource, defaults to C<text/plain>.

=item name

  name => 'Resource Name'

Name of the resource.

=back

=head2 structured_result

  my $result = $tool->structured_result({foo => 'bar'}, $is_error);

Returns a structured result in the format of L</"output_schema">, optionally marking it as an error. Data that does
not match L</"output_schema"> is turned into an error result instead.

=head2 text_result

  my $result = $tool->text_result('Some text', $is_error);

Returns a text result in the expected format, optionally marking it as an error.

=head2 validate_input

  my $bool = $tool->validate_input($args);

Validates the input arguments against L</"input_schema">. Returns true if validation failed. References are only
resolved as JSON pointers into the schema itself, so a C<$ref> to a remote schema is never fetched over the network
and simply fails validation.

=head2 validate_output

  my $bool = $tool->validate_output($data);

Validates structured content against L</"output_schema">. Returns true if validation failed, and false if the tool
has no output schema.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
