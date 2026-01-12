package MCP::Tool;
use Mojo::Base -base, -signatures;

use JSON::Validator;
use Mojo::JSON   qw(false to_json true);
use Mojo::Util   qw(b64_encode);
use Scalar::Util qw(blessed);

has annotations  => sub { {} };
has code         => sub { die 'Tool code not implemented' };
has description  => 'Generic MCP tool';
has input_schema => sub { {type => 'object'} };
has name         => 'tool';
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

sub context ($self) { $self->{context} || {} }

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
  my $result = $self->text_result(to_json($data), $is_error);
  $result->{structuredContent} = $data;
  return $result;
}

sub text_result ($self, $text, $is_error = 0) {
  return {content => [{type => 'text', text => "$text"}], isError => $is_error ? true : false};
}

sub validate_input ($self, $args) {
  unless ($self->{validator}) {
    my $validator = $self->{validator} = JSON::Validator->new;
    $validator->schema($self->input_schema);
  }

  my @errors = $self->{validator}->validate($args);
  return @errors ? 1 : 0;
}

sub _type_check ($self, $result) {
  return $result if ref $result eq 'HASH' && exists $result->{content};
  return $self->text_result($result);
}

1;

=encoding utf8

=head1 NAME

MCP::Tool - Tool container

=head1 SYNOPSIS

  use MCP::Tool;

  my $tool = MCP::Tool->new;

=head1 DESCRIPTION

L<MCP::Tool> is a container for tools to be called.

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

JSON schema for validating input arguments.

=head2 name

  my $name = $tool->name;
  $tool    = $tool->name('my_tool');

Name of the tool.

=head2 output_schema

  my $schema = $tool->output_schema;
  $tool      = $tool->output_schema({type => 'object', properties => {foo => {type => 'string'}}});

JSON schema for validating output results.

=head1 METHODS

L<MCP::Tool> inherits all methods from L<Mojo::Base> and implements the following new ones.

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

=head2 context

  my $context = $tool->context;

Returns the context in which the tool is executed.

  # Get controller for requests using the HTTP transport
  my $c = $tool->context->{controller};

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

Returns a structured result in the format of L</"output_schema">, optionally marking it as an error.

=head2 text_result

  my $result = $tool->text_result('Some text', $is_error);

Returns a text result in the expected format, optionally marking it as an error.

=head2 validate_input

  my $bool = $tool->validate_input($args);

Validates the input arguments against the tool's input schema. Returns true if validation failed.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
