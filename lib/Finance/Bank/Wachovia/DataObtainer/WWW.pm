package Finance::Bank::Wachovia::DataObtainer::WWW;

use WWW::Mechanize;
use HTTP::Cookies;
use Finance::Bank::Wachovia::DataObtainer::WWW::Parser;
use Carp;
use strict;
use warnings;

our $VERSION = '0.1';
my @attrs;

BEGIN{ 
	@attrs = qw(
		customer_access_number
		user_id
		pin
		code_word
		cached_content		
		mech
		start_url
		logged_in
	);
	
	my $x = 0;
	for( @attrs ){
		eval "sub _$_ { $x }";
		$x++;
	}
}

sub new {
	my($class, %attrs) = @_;
	my $self = [];
	bless $self, $class;	
	foreach my $att ( keys %attrs ){
		$self->$att( $attrs{$att} );	
	}
	$self->init();
	return $self;
}

sub init {
	no strict;
	my $self = shift;
	$self->start_url('http://www.wachovia.com/myaccounts') 
		unless $self->start_url;
	$self->[ &{"_cached_content"} ] = {};
}

sub AUTOLOAD {
	no strict 'refs';
	our $AUTOLOAD;
	my $self = shift;
	my $attr = lc $AUTOLOAD;
	$attr =~ s/.*:://;
	croak "$attr not a valid attribute"
		unless grep /$attr/, @attrs;
	# get if no args passed
	return $self->[ &{"_$attr"} ] unless @_;	
	# set if args passed
	$self->[ &{"_$attr"} ] = shift;
	return $self; 
}

sub trash_cache {
	my $self = shift;
	$self->[ &{"_cached_content"} ] = {};	
}

sub get_account_numbers {
	my $self = shift;
	return Finance::Bank::Wachovia::DataObtainer::WWW::Parser
		->get_account_numbers( $self->get_summary_content() );
}

sub get_account_available_balance {
	my $self = shift;
	die "must pass account number" unless @_;
	return Finance::Bank::Wachovia::DataObtainer::WWW::Parser
		->get_account_available_balance( $self->get_summary_content(), @_ );
}

sub get_account_name {
	my $self = shift;
	die "must pass account number" unless @_;
	return Finance::Bank::Wachovia::DataObtainer::WWW::Parser
		->get_account_name( $self->get_summary_content(), @_ );
}

sub get_account_type {
	my($self) = shift;
	die "must pass account number" unless @_;
	return Finance::Bank::Wachovia::DataObtainer::WWW::Parser
		->get_account_type( $self->get_detail_content(@_) );	
}

sub get_account_posted_balance {
	my $self = shift;
	die "must pass account number" unless @_;
	return Finance::Bank::Wachovia::DataObtainer::WWW::Parser
		->get_account_posted_balance( $self->get_detail_content(@_) );
}

sub get_account_transactions {
	my $self = shift;
	die "must pass account number" unless @_;
	return Finance::Bank::Wachovia::DataObtainer::WWW::Parser
		->get_account_transactions( $self->get_detail_content(@_) );
}

sub get_summary_content {
	my $self = shift;
	if( $self->cached_content->{'summary'} ){
		return $self->cached_content->{'summary'};
	}
	if( ! $self->logged_in ){
		$self->login;	
		return $self->cached_content->{'summary'};
	}
	my $mech = $self->mech();
	$mech->form_number( 1 );
	$mech->field( inputName => 'RelationshipSummary' );
	$mech->submit();
	$self->cached_content->{'summary'} = $mech->content();
	return $self->cached_content->{'summary'};
}

sub get_detail_content {
	my($self, $account_number) = @_;
	die "get_detail_content in WWW must have account_number, got: '$account_number'"
		unless $account_number;
	if( $self->cached_content->{'details'}{$account_number} ){
		return $self->cached_content->{'details'}->{$account_number};
	}
	unless( $self->cached_content->{'summary'} ){
		$self->get_summary_conent();	
	}
	my $mech = $self->mech();
	$mech->form_number( 1 );
	$mech->field( RelSumAcctSel		=> $account_number );
	$mech->field( inputName			=> 'AccountDetail' );
	$mech->field( RelSumStmtType		=> 'AccountDetail' );
	$mech->submit();	
	$self->cached_content->{'details'}->{$account_number} = $mech->content();
	# return to summary page
	$mech->form_number( 1 );
	$mech->field( inputName => 'RelationshipSummary' );
	$mech->submit();
	return $self->cached_content->{'details'}->{$account_number};
}

# initilizes WWW::Mech object, uses it to get to summary page
# summary page is cached/overwritten
sub login {
	my $self = shift;
	my %p = @_;
	die "Must set customer_access_number attribute\n"
		unless $self->customer_access_number;
	die "Must set pin attribute\n"
		unless $self->pin;
	die "Must set code_word attribute\n"
		unless $self->code_word;
	my $start = $p{'start_url'} || $self->start_url();

	# now we can get to business
	my $mech = WWW::Mechanize->new(
		autocheck => 1,
		redirect => 1,
	);
	
	# caches the mech object
	$self->mech( $mech );

	$mech->cookie_jar(HTTP::Cookies->new());	# have to turn on cookies manually apparently
	$mech->agent_alias( 'Mac Safari' );			# don't want the bank to know we are geniuses, 
												# but we don't want them thinking we are dumb either.

	# make first contact
	# TODO: add in success checking
	$mech->get( $start );
	# the website uses javascript to set this cookie, so we have to do it manually.
	# without this, an error is returned from the website about either javascript or cookies being turned off
	$mech->cookie_jar->set_cookie( undef, 'CookiesAreEnabled', 'yes', '/', '.wachovia.com', undef, undef, 1 ); 
	#$mech->max_redirect(1);
	#$mech->requests_redirectable([]);
	$mech->form_name( 'canAuthForm' );
	$mech->field( action			=> 'canPinLogin' );
	$mech->field( CAN				=> $self->customer_access_number );
	$mech->field( PIN				=> $self->pin );
	$mech->field( CODEWORD			=> $self->code_word );
	$mech->field( systemtarget		=> 'gotoBanking' );
	$mech->field( requestTimestamp	=> time() ); # the website uses javascript to set this value
	$mech->submit();

	# after the initial commit, there is what appears to be a bunch of redirects. While there are some, there are
	# also some javascript onLoad submits.  The following code emulates that behavior (just submits a form that 
	# has a bunch of hidden inputs )
	$mech->form_name( 'authForm' );
	$mech->submit();

	$mech->form_name( 'autoposterForm' );
	$mech->submit();
	
	$self->cached_content->{'summary'} = $mech->content();
	$self->logged_in( 1 );
	return $self;
}

sub DESTROY {}