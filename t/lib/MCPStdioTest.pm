package MCPStdioTest;
use Mojo::Base -base, -signatures;

use Carp        qw(croak);
use IPC::Run    qw(finish pump start timeout);
use Time::HiRes qw(sleep);
use Mojo::JSON  qw(decode_json encode_json);

sub notify ($self, $method, $params) {
  my $notification = {jsonrpc => '2.0', method => $method, params => $params};
  $self->{timeout}->start(60);
  $self->{stdin} .= encode_json($notification) . "\n";
  return 1;
}

sub request ($self, $method, $params) {
  my $id      = $self->{id} = $self->{id} ? $self->{id} + 1 : 1;
  my $request = {jsonrpc => '2.0', method => $method, params => $params, id => $id};
  $self->{timeout}->start(60);
  $self->{stdin} .= encode_json($request) . "\n";

  my $stdout = $self->{stdout};
  pump $self->{run} until $self->{stdout} =~ s/^(.*)\n//;
  my $input = $1;
  my $res   = eval { decode_json($input) };
  return $res;
}

sub run ($self, @command) {
  $self->{run} = start(\@command, \$self->{stdin}, \$self->{stdout}, \$self->{stderr}, $self->{timeout} = timeout(60));
}

sub stop ($self) {
  return undef unless $self->{run};
  finish($self->{run}) or croak "Command returned: $?";
  delete $self->{run};
  return 1;
}

1;
