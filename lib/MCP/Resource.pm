package MCP::Resource;
use Mojo::Base -base, -signatures;

use Scalar::Util qw(blessed);

has code        => sub { die 'Resource code not implemented' };
has description => 'Generic MCP resource';
has mime_type   => 'text/plain';
has name        => 'resource';
has uri         => 'file://unknown';

sub call ($self, $context) {
  local $self->{context} = $context;
  my $result = $self->code->($self);
  return $result->then(sub { $self->_type_check($_[0]) }) if blessed($result) && $result->isa('Mojo::Promise');
  return $self->_type_check($result);
}

sub context ($self) { $self->{context} || {} }

sub text_resource ($self, $text) {
  my $result = {contents => [{uri => $self->uri, mimeType => $self->mime_type, text => $text}]};
  return $result;
}

sub _type_check ($self, $result) {
  return $result if ref $result eq 'HASH' && exists $result->{contents};
  return $self->text_resource($result);
}

1;

=encoding utf8

=head1 NAME

MCP::Resource - Resource container

=head1 SYNOPSIS

  use MCP::Resource;

  my $resource = MCP::Resource->new;

=head1 DESCRIPTION

L<MCP::Resource> is a container for resources.

=head1 ATTRIBUTES

L<MCP::Resource> implements the following attributes.

=head2 code

  my $code  = $resource->code;
  $resource = $resource->code(sub { ... });

Resource code.

=head2 description

  my $description = $resource->description;
  $resource       = $resource->description('A brief description of the resource');

Description of the resource.

=head2 mime_type

  my $mime_type = $resource->mime_type;
  $resource     = $resource->mime_type('text/plain');

MIME type of the resource.

=head2 name

  my $name  = $resource->name;
  $resource = $resource->name('my_resource');

Name of the resource.

=head2 uri

  my $uri  = $resource->uri;
  $resource = $resource->uri('file:///path/to/resource.txt');

URI of the resource.

=head1 METHODS

L<MCP::Resource> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 call

  my $result = $resource->call($context);

Calls the resource with context, returning a result. The result can be a promise or a direct value.

=head2 context

  my $context = $resource->context;

Returns the context in which the resouce is executed.

  # Get controller for requests using the HTTP transport
  my $c = $resource->context->{controller};

=head2 text_resource

  my $result = $resource->text_resource('Some text');

Returns a text resource in the expected format.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
