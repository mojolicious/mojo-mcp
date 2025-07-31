package MCP::Tool;
use Mojo::Base -base, -signatures;

use JSON::Validator;
use Mojo::JSON   qw(false true);
use Scalar::Util qw(blessed);

has code         => sub { die 'Tool code not implemented' };
has description  => 'Generic MCP tool';
has input_schema => sub { {} };
has name         => 'tool';

sub call ($self, $args) {
  my $result = $self->code->($self, $args);
  return $result->then(sub { $self->_type_check($_[0]) }) if blessed($result) && $result->isa('Mojo::Promise');
  return $self->_type_check($result);
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
