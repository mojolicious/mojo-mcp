package MCP::Prompt;
use Mojo::Base -base, -signatures;

use Scalar::Util qw(blessed);

has arguments   => sub { [] };
has code        => sub { die 'Prompt code not implemented' };
has description => 'Generic MCP prompt';
has name        => 'prompt';

sub call ($self, $args, $context) {
  local $self->{context} = $context;
  my $result = $self->code->($self, $args);
  return $result->then(sub { $self->_type_check($_[0]) }) if blessed($result) && $result->isa('Mojo::Promise');
  return $self->_type_check($result);
}

sub context ($self) { $self->{context} || {} }

sub text_prompt ($self, $text, $role = 'user', $description = undef) {
  my $result = {messages => [{role => $role, content => {type => 'text', text => "$text"}}]};
  $result->{description} = $description if defined $description;
  return $result;
}

sub validate_input ($self, $args) {
  for my $arg (@{$self->arguments}) {
    next     unless $arg->{required};
    return 1 unless exists $args->{$arg->{name}};
  }
  return 0;
}

sub _type_check ($self, $result) {
  return $result if ref $result eq 'HASH' && exists $result->{messages};
  return $self->text_prompt($result);
}

1;

=encoding utf8

=head1 NAME

MCP::Prompt - Prompt container

=head1 SYNOPSIS

  use MCP::Prompt;

  my $prompt = MCP::Prompt->new;

=head1 DESCRIPTION

L<MCP::Prompt> is a container for prompts.

=head1 ATTRIBUTES

L<MCP::Prompt> implements the following attributes.

=head2 arguments

  my $args = $prompt->arguments;
  $prompt   = $prompt->arguments([{name => 'foo', description => 'Whatever', required => 1}]);

Arguments for the prompt.

=head2 code

  my $code = $prompt->code;
  $prompt  = $prompt->code(sub { ... });

Prompt code.

=head2 description

  my $description = $prompt->description;
  $prompt         = $prompt->description('A brief description of the prompt');

Description of the prompt.

=head2 name

  my $name = $prompt->name;
  $prompt  = $prompt->name('my_prompt');

Name of the Prompt.

=head1 METHODS

L<MCP::Prompt> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 call

  my $result = $prompt->call($args, $context);

Calls the prompt with the given arguments and context, returning a result. The result can be a promise or a direct
value.

=head2 context

  my $context = $prompt->context;

Returns the context in which the prompt is executed.

  # Get controller for requests using the HTTP transport
  my $c = $prompt->context->{controller};

=head2 text_prompt

  my $result = $prompt->text_prompt('Some text');
  my $result = $prompt->text_prompt('Some text', $role);
  my $result = $prompt->text_prompt('Some text', $role, $description);

Returns a text prompt in the expected format.

=head2 validate_input

  my $bool = $prompt->validate_input($args);

Validates the input arguments. Returns true if validation failed.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
