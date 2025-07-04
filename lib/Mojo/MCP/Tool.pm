package Mojo::MCP::Tool;
use Mojo::Base -base, -signatures;

has code         => sub { die 'Tool code not implemented' };
has description  => 'Generic MCP tool';
has input_schema => sub { {} };
has name         => 'tool';

sub call ($self, $args) {
  return $self->code->($args);
}

1;
