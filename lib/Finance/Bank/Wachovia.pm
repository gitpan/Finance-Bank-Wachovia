package Finance::Bank::Wachovia;

use Carp;
use Finance::Bank::Wachovia::Account;
use Finance::Bank::Wachovia::Transaction;
use Finance::Bank::Wachovia::DataObtainer::WWW;
use strict;
use warnings;

our $VERSION = '0.1';
my @attrs;

BEGIN{ 
	@attrs = qw(
		customer_access_number
		pin
		code_word
		accounts
		data_obtainer
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
	my $data_obtainer = Finance::Bank::Wachovia::DataObtainer::WWW->new(
		customer_access_number => $self->customer_access_number,
		pin					=> $self->pin,
		code_word			=> $self->code_word	
	);
	$self->data_obtainer( $data_obtainer );		
	$self->accounts({});
	return $self;
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

sub account_numbers {
	my $self = shift;	
	my $do = $self->data_obtainer();
	return $do->get_account_numbers();
}

sub account_names {
	my $self = shift;	
	my $do = $self->data_obtainer();
	return map { $do->get_account_name($_) } $self->account_numbers();
}

sub account_balances {
	my $self = shift;
	my $do = $self->data_obtainer();
	return map { $do->get_account_available_balance($_) } $self->account_numbers();	
}

sub account {
	my($self, $account_number) = @_;	
	if( exists $self->accounts->{$account_number} ){
		return $self->accounts->{$account_number};
	}
	carp "must pass valid account number to account(), got '$account_number'"
		unless $account_number =~ /^\d+$/;
	my $do = $self->data_obtainer();
	#note: we don't set posted_balance here, since that requires extra
	# work by the obtainer, we defer the retrieval of that until it's 
	# needed (asked for via $account->posted_balance)
	my $account = Finance::Bank::Wachovia::Account->new(
		number				=> $account_number,
		data_obtainer		=> $do,
	);
	unless( $account ){
		croak "Could not create account object";	
	}
	$self->accounts->{$account_number} = $account;
	return $account;
}

sub DESTROY {}

__END__

=begin

=head1 NAME

Finance::Bank::Wachovia - access account info from Perl

=over 1

=item * Account numbers

=item * Account names

=item * Account balances (posted and available)

=item * Account transaction data (in all their detailed glory)

=back

Does not (yet) provide any means to transfer money or pay bills.

=head1 SYNOPSIS

Since this version uses the website to get account info, it will need the information to login:
Customer access number, Pin, and Code word.  The "other way" to log in is not currently supported*.

  use Finance::Bank::Wachovia;
  
  my $wachovia  = Finance::Bank::Wachovia->new(
  	customer_access_number => '123456789',
  	pin	=> '1234',
  	code_word	=> 'blah'
  );
  
  my @account_numbers		= $wachovia->account_numbers();
  my @account_names		= $wachovia->account_names();
  my @account_balances	= $wachovia->account_balanes();

  my $account = $wachovia->account( $account_numbers[0] );
  print "Number: ", $account->number, "\n";
  print "Name: ", $account->name, "\n";
  print "Type: ", $account->type, "\n";
  print "Avail. Bal.: ", $account->available_balance, "\n";
  print "Posted.Bal.: ", $account->posted_balance, "\n";
  
  my $transactions = $account->transactions;
  
  foreach my $t ( @$transactions ){
  	print "Date: ",     $t->date,              "\n",
  	      "Action: ",   $t->action,            "\n",
  	      "Desc: ",     $t->description,       "\n",
  	      "Withdrawal", $t->withdrawal_amount, "\n",
  	      "Deposit",    $t->deposit_amount,    "\n",
  	      "Balance",    $t->balance,           "\n",
  	      "seq_no",     $t->seq_no,            "\n",
  	      "trans_code", $t->trans_code,        "\n",
  	      "check_num",  $t->check_num,         "\n";
  } 
  

=head1 DESCRIPTION

Internally uses WWW::Mechanize to scrape the bank's website.  The idea was to keep
the interface as logical as possible.  The user is completely abstracted from how the
data is obtained, and to a large degree so is the module itself.  In case wachovia ever offers
an XML interface, or even soap, this should be an easy module to add to, but the interface will
not change, so your code won't have too either.

=head1 METHODS

=head2 new

Returns object, you should pass 3 parameters: your Customer access number, your PIN, 
and your Code word.  These will be used when the module accesses the wachovia website.

  my $wachovia = Finance::Bank::Wachovia->new(
    customer_access_number => '123456789',
  	pin	=> '1234',
  	code_word	=> 'blah'
  );
  
=head2 account_numbers

Returns a list of account numbers (from the Relationship Summary Page).

  my @numbers = $wachovia->account_numbers();
  
=head2 account_names

Returns (in lowercase) a list of account names (ie: "exp access") (from the Relationship Summary Page).

  my @names = $wachovia->account_names;
  
=head2 account_balances

Returns a list of account balances (from Relationship Summary page ).

  my @balances = $wachovia->account_balances;
  
=head2 account

Returns a Finance::Bank::Wachovia::Account object.  This object can be used to 
get any info available about an account, including posted/available balances, 
it's name, type, number, and a list of all it's transactions.  See the perldocs for
Finance::Bank::Wachovia::Account for info on what to do with the object. (or just look at the
code example in the "How to use" section of this perldoc.

  my $account = $wachovia->account( $account_num );

=head1 WORTH MENTIONING

Doug Feuerbach had the idea for storing login information in an encrypted file to be accessed via a password (like apple's keychain).  
Then he gave me the code to implement it.  He thinks it's silly to thank him for something "so trivial", but he should know that
it's not an official perl module without a "thanks" going out to someone by name.  The program included with the module makes use of 
his contribution.  Thanks Doug.

Also, thanks to the Giants that authored all the modules that made the conception and creation of this module so easy.  Your shoulder's are awesome.
 
=head1 TODO

=over 1

=item * finish documentation

=item * add proper exception/error handling

=item * add in support for "other login" method (user/pin vs can/pin/codeword)

=item * add in fancy stuff like transfers and billpay -- maybe

=back
  
=head1 AUTHOR

Jim Garvin E<lt>jg.perl@thegarvin.comE<gt>

Copyright 2004 by Jim Garvin

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=head1 SEE ALSO

Finance::Bank::Wachovia::Account  Finance::Bank::Wachovia::Transaction

=cut

