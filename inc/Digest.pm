#line 1 "inc/Digest.pm - /usr/local/lib/perl5/5.8.2/Digest.pm"
package Digest;

use strict;
use vars qw($VERSION %MMAP $AUTOLOAD);

$VERSION = "1.02";

%MMAP = (
  "SHA-1"      => "Digest::SHA1",
  "HMAC-MD5"   => "Digest::HMAC_MD5",
  "HMAC-SHA-1" => "Digest::HMAC_SHA1",
);

sub new
{
    shift;  # class ignored
    my $algorithm = shift;
    my $class = $MMAP{$algorithm} || "Digest::$algorithm";
    no strict 'refs';
    unless (exists ${"$class\::"}{"VERSION"}) {
	eval "require $class";
	die $@ if $@;
    }
    $class->new(@_);
}

sub AUTOLOAD
{
    my $class = shift;
    my $algorithm = substr($AUTOLOAD, rindex($AUTOLOAD, '::')+2);
    $class->new($algorithm, @_);
}

1;

__END__

#line 187
