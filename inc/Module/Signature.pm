#line 1 "inc/Module/Signature.pm - /usr/local/lib/perl5/site_perl/5.8.2/Module/Signature.pm"
# $File: //member/autrijus/Module-Signature/lib/Module/Signature.pm $ 
# $Revision: #27 $ $Change: 8703 $ $DateTime: 2003/11/06 10:50:49 $

package Module::Signature;
$Module::Signature::VERSION = '0.37';

use strict;
use vars qw($VERSION $SIGNATURE @ISA @EXPORT_OK);
use vars qw($Preamble $Cipher $Debug $Verbose);
use vars qw($KeyServer $KeyServerPort $AutoKeyRetrieve $CanKeyRetrieve); 

use constant CANNOT_VERIFY       => "0E0";
use constant SIGNATURE_OK        => 0;
use constant SIGNATURE_MISSING   => -1;
use constant SIGNATURE_MALFORMED => -2;
use constant SIGNATURE_BAD       => -3;
use constant SIGNATURE_MISMATCH  => -4;
use constant MANIFEST_MISMATCH   => -5;
use constant CIPHER_UNKNOWN      => -6;

use ExtUtils::Manifest ();
use Exporter;

@EXPORT_OK	= (qw(sign verify),
		   qw($SIGNATURE $KeyServer $Cipher $Preamble),
		   grep /^[A-Z_]+_[A-Z_]+$/, keys %Module::Signature::);
@ISA		= 'Exporter';

$SIGNATURE	= 'SIGNATURE';
$Verbose        = $ENV{MODULE_SIGNATURE_VERBOSE} || 0;
$KeyServer	= $ENV{MODULE_SIGNATURE_KEYSERVER} || 'pgp.mit.edu';
$KeyServerPort	= $ENV{MODULE_SIGNATURE_KEYSERVERPORT} || '11371';
$Cipher		= 'SHA1';
$Preamble	= << ".";
This file contains message digests of all files listed in MANIFEST,
signed via the Module::Signature module, version $VERSION.

To verify the content in this distribution, first make sure you have
Module::Signature installed, then type:

    % cpansign -v

It would check each file's integrity, as well as the signature's
validity.  If "==> Signature verified OK! <==" is not displayed,
the distribution may already have been compromised, and you should
not run its Makefile.PL or Build.PL.

.

$AutoKeyRetrieve    = 1;
$CanKeyRetrieve	    = undef;

#line 285

sub verify {
    my %args = ( skip => 1, @_ );
    my $rv;

    (-r $SIGNATURE) or do {
	warn "==> MISSING Signature file! <==\n";
	return SIGNATURE_MISSING;
    };

    (my $sigtext = _read_sigfile($SIGNATURE)) or do {
	warn "==> MALFORMED Signature file! <==\n";
	return SIGNATURE_MALFORMED;
    };

    (my ($cipher) = ($sigtext =~ /^(\w+) /)) or do {
	warn "==> MALFORMED Signature file! <==\n";
	return SIGNATURE_MALFORMED;
    };

    (defined(my $plaintext = _mkdigest($cipher))) or do {
	warn "==> UNKNOWN Cipher format! <==\n";
	return CIPHER_UNKNOWN;
    };

    $rv = _verify($SIGNATURE, $sigtext, $plaintext);

    if ($rv == SIGNATURE_OK) {
	my ($mani, $file) = _fullcheck($args{skip});

	if (@{$mani} or @{$file}) {
	    warn "==> MISMATCHED content between MANIFEST and distribution files! <==\n";
	    return MANIFEST_MISMATCH;
	}
	else {
	    warn "==> Signature verified OK! <==\n" if $Verbose;
	}
    }
    elsif ($rv == SIGNATURE_BAD) {
	warn "==> BAD/TAMPERED signature detected! <==\n";
    }
    elsif ($rv == SIGNATURE_MISMATCH) {
	warn "==> MISMATCHED content between SIGNATURE and distribution files! <==\n";
    }

    return $rv;
}

sub _verify {
    my $signature = shift || $SIGNATURE;
    my $sigtext   = shift || '';
    my $plaintext = shift || '';

    local $SIGNATURE = $signature if $signature ne $SIGNATURE;

    if ($AutoKeyRetrieve and !$CanKeyRetrieve) {
	if (!defined $CanKeyRetrieve) {
	    require IO::Socket::INET;
	    my $sock = IO::Socket::INET->new("$KeyServer:$KeyServerPort");
	    $CanKeyRetrieve = ($sock ? 1 : 0);
	    $sock->shutdown(2) if $sock;
	}
	$AutoKeyRetrieve = $CanKeyRetrieve;
    }

    if (`gpg --version` =~ /GnuPG.*?(\S+)$/m) {
	return _verify_gpg($sigtext, $plaintext, $1);
    }
    elsif (eval {require Crypt::OpenPGP; 1}) {
	return _verify_crypt_openpgp($sigtext, $plaintext);
    }
    else {
	warn "Cannot use GnuPG or Crypt::OpenPGP, please install either one first!\n";
	return _compare($sigtext, $plaintext, CANNOT_VERIFY);
    }
}

sub _fullcheck {
    my $skip = shift;
    my @extra;

    local $^W;
    local $ExtUtils::Manifest::Quiet = 1;

    my($mani, $file);
    if( _legacy_extutils() ) {
        my $_maniskip = &ExtUtils::Manifest::_maniskip;

        local *ExtUtils::Manifest::_maniskip = sub { sub {
	    return unless $skip;
	    my $ok = $_maniskip->(@_);
	    if ($ok ||= (!-e 'MANIFEST.SKIP' and _default_skip(@_))) {
	        print "Skipping $_\n" for @_;
	        push @extra, @_;
	    }
	    return $ok;
        } };

        ($mani, $file) = ExtUtils::Manifest::fullcheck();
    }
    else {
        ($mani, $file) = ExtUtils::Manifest::fullcheck();
    }

    foreach my $makefile ('Makefile', 'Build') {
	warn "==> SKIPPED CHECKING '$_'!" .
		(-e "$_.PL" && " (run $_.PL to ensure its integrity)") .
		" <===\n" for grep $_ eq $makefile, @extra;
    }

    @{$mani} = grep {$_ ne 'SIGNATURE'} @{$mani};

    warn "Not in MANIFEST: $_\n" for @{$file};
    warn "No such file: $_\n" for @{$mani};

    return ($mani, $file);
}

sub _legacy_extutils {
    # ExtUtils::Manifest older than 1.41 does not handle default skips well.
    return (ExtUtils::Manifest->VERSION < 1.41);
}

sub _default_skip {
    local $_ = shift;
    return 1 if /\bRCS\b/ or /\bCVS\b/ or /\B\.svn\b/ or /,v$/
	     or /^MANIFEST\.bak/ or /^Makefile$/ or /^blib\//
	     or /^MakeMaker-\d/ or /^pm_to_blib$/
	     or /^_build\// or /^Build$/
	     or /~$/ or /\.old$/ or /\#$/ or /^\.#/;
}

sub _verify_gpg {
    my ($sigtext, $plaintext, $version) = @_;

    local $SIGNATURE = Win32::GetShortPathName($SIGNATURE)
	if defined &Win32::GetShortPathName and $SIGNATURE =~ /[^-\w.:~\\\/]/;

    my $scheme = "x-hkp";
    $scheme = "hkp" if $version ge "1.2.0";
    my @quiet = $Verbose ? () : qw(-q --logger-fd=1);
    my @cmd = (
	qw(gpg --verify --batch --no-tty), @quiet, ($KeyServer ? (
	    "--keyserver=$scheme://$KeyServer:$KeyServerPort",
	    ($AutoKeyRetrieve and $version ge "1.0.7")
		? "--keyserver-options=auto-key-retrieve"
		: ()
	) : ()), $SIGNATURE
    );

    my $output = '';
    if( $Verbose ) {
        system @cmd;
    }
    else {
        my $cmd = join ' ', @cmd;
        $output = `$cmd`;
    }

    if( $? ) {
        print STDERR $output;
    }
    elsif ($output =~ /((?: +[\dA-F]{4}){10,})/) {
	warn "WARNING: This key is not certified with a trusted signature!\n";
        warn "Primary key fingerprint:$1\n";
    }

    return SIGNATURE_BAD if ($? and $AutoKeyRetrieve);
    return _compare($sigtext, $plaintext, (!$?) ? SIGNATURE_OK : CANNOT_VERIFY);
}

sub _verify_crypt_openpgp {
    my ($sigtext, $plaintext) = @_;

    require Crypt::OpenPGP;
    my $pgp = Crypt::OpenPGP->new(
	($KeyServer) ? ( KeyServer => $KeyServer, AutoKeyRetrieve => $AutoKeyRetrieve ) : (),
    );
    my $rv = $pgp->handle( Filename => $SIGNATURE )
	or die $pgp->errstr;

    return SIGNATURE_BAD if (!$rv->{Validity} and $AutoKeyRetrieve);

    if ($rv->{Validity}) {
	warn "Signature made ", scalar localtime($rv->{Signature}->timestamp),
	     " using key ID ", substr(uc(unpack("H*", $rv->{Signature}->key_id)), -8), "\n",
	     "Good signature from \"$rv->{Validity}\"\n" if $Verbose;
    }
    else {
	warn "Cannot verify signature; public key not found\n";
    }

    return _compare($sigtext, $plaintext, $rv->{Validity} ? SIGNATURE_OK : CANNOT_VERIFY);
}

sub _read_sigfile {
    my $sigfile = shift;
    my $signature = '';
    my $well_formed;

    local *D;
    open D, $sigfile or die "Could not open $sigfile: $!";
    while (<D>) {
	next if (1 .. /^-----BEGIN PGP SIGNED MESSAGE-----/);
	last if /^-----BEGIN PGP SIGNATURE/;

	$signature .= $_;
    }

    return ((split(/\n+/, $signature, 2))[1]);
}

sub _compare {
    my ($str1, $str2, $ok) = @_;

    # normalize all linebreaks
    $str1 =~ s/[^\S ]+/\n/; $str2 =~ s/[^\S ]+/\n/;

    return $ok if $str1 eq $str2;

    if (eval { require Text::Diff; 1 }) {
	warn "--- $SIGNATURE ".localtime((stat($SIGNATURE))[9])."\n";
	warn "+++ (current) ".localtime()."\n";
	warn Text::Diff::diff( \$str1, \$str2, { STYLE => "Unified" } );
    }
    else {
	local (*D, *S);
	open S, $SIGNATURE or die "Could not open $SIGNATURE: $!";
	open D, "| diff -u $SIGNATURE -" or (warn "Could not call diff: $!", return SIGNATURE_MISMATCH);
	while (<S>) {
	    print D $_ if (1 .. /^-----BEGIN PGP SIGNED MESSAGE-----/);
	    print D if (/^Hash: / .. /^$/);
	    next if (1 .. /^-----BEGIN PGP SIGNATURE/);
	    print D $str2, "-----BEGIN PGP SIGNATURE-----\n", $_ and last;
	}
	print D <S>;
	close D;
    }

    return SIGNATURE_MISMATCH;
}

sub sign {
    my %args = ( skip => 1, @_ );
    my $overwrite = $args{overwrite};
    my $plaintext = _mkdigest();

    my ($mani, $file) = _fullcheck($args{skip});

    if (@{$mani} or @{$file}) {
	warn "==> MISMATCHED content between MANIFEST and the distribution! <==\n";
	warn "==> Please correct your MANIFEST file and/or delete extra files. <==\n";
    }

    if (!$overwrite and -e $SIGNATURE and -t STDIN) {
	local $/ = "\n";
	print "$SIGNATURE already exists; overwrite [y/N]? ";
	return unless <STDIN> =~ /[Yy]/;
    }

    if (`gpg --version` =~ /GnuPG.*?(\S+)$/m) {
	_sign_gpg($SIGNATURE, $plaintext, $1);
    }
    elsif (eval {require Crypt::OpenPGP; 1}) {
	_sign_crypt_openpgp($SIGNATURE, $plaintext);
    }
    else {
	die "Cannot use GnuPG or Crypt::OpenPGP, please install either one first!";
    }

    warn "==> SIGNATURE file created successfully. <==\n";
    return SIGNATURE_OK;
}

sub _sign_gpg {
    my ($sigfile, $plaintext) = @_;

    die "Could not write to $sigfile"
	if -e $sigfile and (-d $sigfile or not -w $sigfile);

    local *D;
    open D, "| gpg --clearsign >> $sigfile.tmp" or die "Could not call gpg: $!";
    print D $plaintext;
    close D;

    (-e "$sigfile.tmp" and -s "$sigfile.tmp") or do {
	unlink "$sigfile.tmp";
	die "Cannot find $sigfile.tmp, signing aborted.\n";
    };

    open D, "$sigfile.tmp" or die "Cannot open $sigfile.tmp: $!";

    open S, ">$sigfile" or do {
	unlink "$sigfile.tmp";
	die "Could not write to $sigfile: $!";
    };

    print S $Preamble;
    print S <D>;

    close S;
    close D;

    unlink("$sigfile.tmp");
    return 1;
}

sub _sign_crypt_openpgp {
    my ($sigfile, $plaintext) = @_;

    require Crypt::OpenPGP;
    my $pgp = Crypt::OpenPGP->new;
    my $ring = Crypt::OpenPGP::KeyRing->new(
	Filename => $pgp->{cfg}->get('SecRing')
    ) or die $pgp->error(Crypt::OpenPGP::KeyRing->errstr);
    my $kb = $ring->find_keyblock_by_index(-1)
	or die $pgp->error("Can't find last keyblock: " . $ring->errstr);

    my $cert = $kb->signing_key;
    my $uid = $cert->uid($kb->primary_uid);
    warn "Debug: acquiring signature from $uid\n" if $Debug;

    my $signature = $pgp->sign(
	Data       => $plaintext,
	Detach     => 0,
	Clearsign  => 1,
	Armour     => 1,
	Key        => $cert,
	PassphraseCallback => \&Crypt::OpenPGP::_default_passphrase_cb,
    ) or die $pgp->errstr;


    local *D;
    open D, ">$sigfile" or die "Could not write to $sigfile: $!";
    print D $Preamble;
    print D $signature;
    close D;

    return 1;
}

sub _mkdigest {
    my $digest = _mkdigest_files(undef, @_) or return;
    my $plaintext = '';

    foreach my $file (sort keys %$digest) {
	next if $file eq $SIGNATURE;
	$plaintext .= "@{$digest->{$file}} $file\n";
    }

    return $plaintext;
}

sub _mkdigest_files {
    my $p = shift;
    my $algorithm = shift || $Cipher;
    my $dosnames = (defined(&Dos::UseLFN) && Dos::UseLFN()==0);
    my $read = ExtUtils::Manifest::maniread() || {};
    my $found = ExtUtils::Manifest::manifind($p);
    my(%digest) = ();
    my $obj = eval { Digest->new($algorithm) } || eval {
	require "Digest/$algorithm.pm"; "Digest::$algorithm"->new
    } or do {
	warn("Unknown cipher: $algorithm\n"); return;
    };

    foreach my $file (sort keys %$read){
        warn "Debug: collecting digest from $file\n" if $Debug;
        if ($dosnames){
            $file = lc $file;
            $file =~ s=(\.(\w|-)+)=substr ($1,0,4)=ge;
            $file =~ s=((\w|-)+)=substr ($1,0,8)=ge;
        }
        unless ( exists $found->{$file} ) {
            warn "No such file: $file\n" if $Verbose;
        }
	else {
	    local *F;
	    open F, $file or die "Cannot open $file for reading: $!";
	    binmode(F) if -B $file;
	    $obj->addfile(*F);
	    $digest{$file} = [$algorithm, $obj->hexdigest];
	    $obj->reset;
	}
    }

    return \%digest;
}

1;

__END__

#line 698
