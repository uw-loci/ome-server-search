# OME/Web.pm

#-------------------------------------------------------------------------------
#
# Copyright (C) 2003 Open Microscopy Environment
#       Massachusetts Institute of Technology,
#       National Institutes of Health,
#       University of Dundee
#
#
#
#    This library is free software; you can redistribute it and/or
#    modify it under the terms of the GNU Lesser General Public
#    License as published by the Free Software Foundation; either
#    version 2.1 of the License, or (at your option) any later version.
#
#    This library is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    Lesser General Public License for more details.
#
#    You should have received a copy of the GNU Lesser General Public
#    License along with this library; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#-------------------------------------------------------------------------------




#-------------------------------------------------------------------------------
#
# Written by:    Douglas Creager <dcreager@alum.mit.edu>
#
#-------------------------------------------------------------------------------

=head1 NAME

OME::Web - The parent class of OME web pages

=head1 SYNOPSIS

	package OME::Web::Home;
	use strict;
	use OME;
	use CGI;
	use base qw/OME::Web/;

	our $VERSION;
	$VERSION = $OME::VERSION;

	sub getPageTitle {
		return "Open Microscopy Environment";
	}

	sub getPageBody {
		$self->contentType('text/html');
		$HTML = <<ENDHTML;
			<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
			<HTML><HEAD>
			<TITLE>Open Microscopy Environment</TITLE>
			<META NAME="ROBOTS" CONTENT="NOINDEX">
			</HEAD>
	ENDHTML	
		return ('HTML', $HTML);
	}
	1;


=head1 DESCRIPTION

This class is meant to be sub-classed by web pages in OME.  This class is only meant to provide common functionality.

=head1 METHODS

=cut


package OME::Web;

use strict;
use vars qw($VERSION);
use OME;
$VERSION = $OME::VERSION;
use CGI;
use Carp;
use Carp 'cluck';
use OME::SessionManager;
use OME::Web::DefaultHeaderBuilder;
use OME::Web::DefaultMenuBuilder;
use OME::Web::DBObjRender;
use OME::Web::Util::Category;
use OME::Web::Util::Dataset;
use OME::Web::Search;

use base qw(Class::Data::Inheritable);

# The OME::Web class serves as the ancestor of all webpages accessed
# through the OME system.  Functionaly common to all pages of the site
# are defined here.	 Each webpage is defined by a subclass (ideally
# with a name prefixed with OME::Web::) which overrides the following
# methods:
#
#	 getPageTitle
#	 getPageBody
#	 

# IGG 9/18/03:
# contentType no longer defined as a method in this package
# to make it easier to modify in subclasses.
__PACKAGE__->mk_classdata('contentType');
__PACKAGE__->contentType('text/html');

my $loginPage = 'OME::Web::Login';

# new()
# -----

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my %params = @_;

	my $CGI;
	if (exists $params{CGI}) {
	$CGI = $params{CGI};
	} else {
	$CGI = new CGI;
	}
	
	my $self = {
	CGI => $CGI
	};

	# Popup info
	$self->{_popup} = 1 if ( $CGI->param('Popup') or $CGI->url_param('Popup') );
	$self->{_nomenu} = 1 if ( $CGI->param('NoMenu') or $CGI->url_param('Popup') );
	$self->{_noheader} = 1 if ( $CGI->param('NoHeader') or $CGI->url_param('Popup') );

	$self->{RequireLogin} = 1;

	$self->{manager} = OME::SessionManager->new();
	
	$self->{_cookies} = undef;
	$self->{_headers} = undef;

	bless($self,$class);
	return $self;
}


# Accessors
# ---------

sub CGI { my $self = shift; return $self->{CGI}; }
sub Manager { my $self = shift; return $self->{manager}; }
sub ApacheSession { my $self = shift; return $self->Session()->{ApacheSession}; }
sub User { my $self = shift; return $self->Session()->User(); }
sub Renderer { 
	my $self = shift; 
	return $self->{renderer} if $self->{renderer};
	return ( $self->{renderer} = OME::Web::DBObjRender->new( CGI => $self->CGI() ) );
}
sub SearchUtil { 
	my $self = shift; 
	return $self->{search_util} if $self->{search_util};
	return ( $self->{search_util} = OME::Web::Search->new( CGI => $self->CGI() ) );
}
sub Tablemaker { 
	my $self = shift; 
	return $self->{ table_maker } if $self->{ table_maker };
	return ( $self->{ table_maker } = OME::Web::DBObjTable->new( CGI => $self->CGI() ) );
}
sub CategoryUtil {
	my $self = shift; 
	return $self->{ category_util } if $self->{ category_util };
	return ( $self->{ category_util } = OME::Web::Util::Category->new( CGI => $self->CGI() ) );
}
sub DatasetUtil {
	my $self = shift; 
	return $self->{ dataset_util } if $self->{ dataset_util };
	return ( $self->{ dataset_util } = OME::Web::Util::Dataset->new( CGI => $self->CGI() ) );
}

# Because we no longer need any sort of Session reference store this is just a macro now
sub Session { OME::Session->instance() };

# redirectURL
# -----------

sub pageURL {
	my ($self, $page, $param) = @_;
	return "serve.pl?Page=$page".
		( $param ?
		  '&'.join( '&', map( $_."=".$param->{$_}, keys %$param ) ) :
		  ''
		);
	#return $self->CGI()->escape("serve.pl?Page=$page");
}


# ensureLogin
# -----------

sub ensureLogin {
	my $self = shift;
	my $manager = $self->Manager();

	#or a new session if we got no cookie my %session;
	my $sessionKey = $self->getSessionKey();

	if (defined $sessionKey) {
		my $session = $manager->createSession($sessionKey);
		if ($session) {
			$self->setSessionCookie($self->Session()->SessionKey());
		} else {
			$self->setSessionCookie();
		}
		return defined $session;
	}

	return;
}


#
# setSessionCookie
# ----------------

sub setSessionCookie {
my $self = shift;
my $sessionKey = shift;
my $cgi = $self->CGI();

	if (defined $sessionKey) {
#print STDERR "\nSetting cookie: $sessionKey\n";
		$self->{_cookies}->{'SESSION_KEY'} =
			$cgi->cookie( -name	   => 'SESSION_KEY',
						  -value   => $sessionKey,
						  -path    => '/',
						  -expires => '+30m'
						  );
	} else {
#print STDERR "\nLogging out - resetting cookie\n";
		$self->{_cookies}->{'SESSION_KEY'} =
			$cgi->cookie( -name	   => 'SESSION_KEY',
						  -value   => '',
						  -path    => '/',
						  -expires => '-1d'
						  );
	}
}


#
# getSessionKey
# ----------------

sub getSessionKey {
	my $self = shift;
	my $cgi = $self->CGI();
	my $key = $cgi->cookie('SESSION_KEY');
	return $key if $key;
	$key = $cgi->url_param('SessionKey');
	return $key if $key;
	$key = $cgi->param('SessionKey');
	return $key;
}


# getLogin()
# ----------

sub getLogin {
	my $self = shift;
	$self->redirect($self->pageURL($loginPage));
}

# serve()
# -------
sub serve {
	my $self = shift;

	# XXX This is our *only* form of access control to the session object
	if ($self->{RequireLogin}) {
		if (!$self->ensureLogin()) {
			$self->getLogin();
			return;
		}
	}

	my ($result,$content,$jnpl_filename) = $self->createOMEPage();
	
	my $cookies = [values %{$self->{_cookies}}];
	my $headers = $self->headers();
	$headers->{'-cookie'} = $cookies if scalar @$cookies;
	$headers->{'-expires'} = '-1d';
	$headers->{'-type'} = $self->contentType();



	# This would be a place to put browser-specific handling if necessary
	if ($result eq 'HTML' && defined $content) {
		print $self->CGI()->header(%{$headers});
		print $content;
	} elsif ($result eq 'TXT' && defined $content) {
		$self->contentType('text/plain');
		$headers->{-type} = $self->contentType();
		print $self->CGI()->header(%{$headers});
		print $content;
	} elsif ($result eq 'IMAGE' && defined $content) {
		print $self->CGI()->header(%{$headers});
		print $content;
	} elsif ($result eq 'SVG' && defined $content) {
		print $self->CGI()->header(%{$headers});
		print $content;
	} elsif ($result eq 'JNLP' && defined $content) {
		$headers->{'-attachment'} = $jnpl_filename;
		print $self->CGI()->header(%{$headers});
		print $content;
	} elsif ($result eq 'FILE' && defined $content && ref($content) eq 'HASH') {
		$self->sendFile ($content);
	} elsif ($result eq 'REDIRECT' && defined $content) {
		# Added here to propagate headers to redirects [Bug #174]
		print $self->CGI()->header(%{$headers});
		$self->redirect($content);
	} else {
		my $class = ref($self);
		print $self->CGI()->header(-type => 'text/html', -status => '500',%{$headers});
		print "You shouldn't be accessing the $class page.";
		print "<br>Here's the error message:<br>$content" unless !(defined $content);
	}
}

sub headers {
	my $self = shift;
	return $self->{_headers};
}

sub sendFile {
	my $self = shift;
	my $params = shift;
	my $downloadFilename;
	
	die "Call to OME::Web::sendFile() without specifying a filename or content!"
		unless exists $params->{filename} or exists $params->{content};	

	$downloadFilename = $params->{downloadFilename}
		if exists $params->{downloadFilename};

	my $headers;
	$headers->{'-attachment'} = $downloadFilename
		if defined $downloadFilename;
	$headers->{'-type'} = $self->contentType();
	print $self->CGI()->header(%$headers);
	
	if (exists $params->{filename}) {
		my $filename = $params->{filename};
		open (INFILE,$filename)
			or die "OME::Web::sendFile() could not open $filename for reading: $!\n";
		my $buffer;
		while (read (INFILE,$buffer,32768)) {
			print $buffer;
		}
		close (INFILE);
		unlink $filename if exists $params->{temp} and $params->{temp};
	} else {
		print $params->{content};
	}
	
}

sub redirect {
	my $self = shift;
	my $URL = shift;

	print $self->CGI()->header (-type=>'text/html', -cookie => [values %{$self->{_cookies}}]);
	print qq {
		<script language="JavaScript"> 	 
			<!-- 	 
				window.location = "$URL"; 	 
			//--> 	 
		</script> 	 
	};
}


# getTopNavbar
# ------------
# this is depricated

sub getTopNavbar {
	my $self = shift;
	my $CGI = $self->CGI();
	
	return $CGI->td($CGI->font(combine($self->{fontDefaults},
					   {size => '+2'}),
				   $CGI->b('OME')).
			"<br>Top navbar");
}

# getSidebar
# ----------
# this is depricated

sub getSidebar {
	my $self	= shift;
	my $CGI		= $self->CGI();
	my $session = $self->Session();

	my $loginMessage = "";
	
	if (defined $session) {
	my $user = $self->User();
	my $firstName = $user->FirstName();
	my $lastName = $user->LastName();
	$loginMessage = "<hr>$firstName $lastName";
	my $url = $self->pageURL('OME::Web::Logout');
	$loginMessage .= "<br><small><a href=\"$url\">LOGOUT</a></small>";
	}

	return	$CGI->td("Sidebar${loginMessage}<hr>Dataset info?<hr>Previously run<br>analyses?");
}

# createOMEPage
# -------------

sub createOMEPage {
	my $self  = shift;
	my $CGI	  = $self->CGI();
	my $title = $self->getPageTitle();
	my ($result,$body)	= $self->getPageBody();
	return ('ERROR',undef) if (!defined $title || !defined $body);
	return ($result,$body) if ($result ne 'HTML');

	my $head = $CGI->start_html(
		-title => $title,
		-style => {'src' => '/html/ome2.css'},
		-script => {-language => 'JAVASCRIPT', -src => '/JavaScript/ome2.js'},
		-onLoad => $self->getOnLoadJS() || '',
	);

	# Header TR, shown and generated only if !undef
	my $header_tr;

	if (my $header_builder = $self->getHeaderBuilder()) {
		$header_tr =
			$CGI->Tr($CGI->td( {
					colspan => '2',
					class => 'ome_header_td',
				}, $header_builder->getPageHeader()));
	}

	# Menu TD and Menu Location TD, shown only if !undef
	my ($menu_td, $menu_location_td);

	if (my $menu_builder = $self->getMenuBuilder()) {
		$menu_td =
			$CGI->td( {
					valign => 'top',
					class => 'ome_main_menu_td',
				}, $menu_builder->getPageMenu());
		$menu_location_td =
			$CGI->td( {
					class => 'ome_location_menu_td',
				}, $menu_builder->getPageLocationMenu());
	}

	# Body / Menu Location Table and TD generated only if menu_location
	my ($body_table, $body_td);

	if ($menu_location_td) { 
		$body_table = $CGI->table({width => '100%'},
			$CGI->Tr( [
				$menu_location_td,
				$CGI->td({valign => 'top', width => '100%'}, $body),
				])
		);
		
		$body_td = $CGI->td({valign => 'top', width => '100%'}, $body_table);
	} else {
		$body_td = $CGI->td({valign => 'top', width => '100%'}, $body);
	}

	# Main TR for the menu and body
	my $main_tr;

	if ($menu_td) {
		$main_tr = $CGI->Tr($menu_td . $body_td);
	} else {
		$main_tr = $CGI->Tr($body_td);
	}

	# Packing table for the entire page
	$body = $CGI->table( {
			class       => 'ome_page_table',
			cellspacing => '0',
			cellpadding => '3',
		},
		$header_tr || '',
		$main_tr,
	);
		 		 
	my $tail = $CGI->end_html;

	return ('HTML', $head . $body . $tail);
}


=head2 getPageTitle

This method should be over-ridden in a sub-class and return a text string with the page title,
which will normally appear in the window's title bar.

=cut

# getPageTitle()
# --------------
# This should be overriden in descendant classes to return the title
# of the page.

sub getPageTitle {
	return undef;
}


=head2 getPageBody

This method must be over-ridden in a sub-class and return two scalars.
The first scalar is treated as a status message to determine what to do with the second scalar.  For example,

  return ('HTML',$HTML);

Accepted status strings are C<HTML>, C<IMAGE>, C<SVG>, C<JNLP>, C<FILE>, C<REDIRECT> and C<ERROR>,
If the returned status is C<HTML>, then the page is appropriately decorated to match the other pages in OME.
No special processing is currently done for C<IMAGE>, C<SVG>, and C<JNLP>. For C<JNLP> the filename that should
be used on the client must also be returned e.g. 
  
  return ('JNLP', $JNLP, $filename);

A C<FILE> status is used for downloading files to the browser.  In this case, the second scalar is a hash reference
containing information to control the download process.  The hash may contain the following:

 filename         - a path to the file on the server to be downloaded.
 downloadFilename - The name of the file that should be used on the client (the browser).
 temp             - A flag that if true, will cause the downloaded file to be deleted on the server.

 return ('FILE',{filename => $myFile, downloadFilename => 'foo.txt', temp => 1});

A C<REDIRECT> status is used to get the browser to go to a different URL specified by the second scalar:

  return ('REDIRECT','http://ome.org/somewhere/else.html');

A C<ERROR> status means an error has occurred.  The error message should be sent as the second scalar.

  return ('ERROR','Something really bad happened');

The script can generate the same effect by calling

  die ('Something really bad happened');

=cut

# getPageBody()
# -------------
# This should be overridden in descendant classes to return the body
# of the page.	It should be returned as a tuple in the following
# form:

#
#	('ERROR',<error message>)
#	   - something unexpectedly bad happened
#
#	('HTML',<page body>)
#	   - everything worked well, returns an HTML fragment for the body
#		 of the page
#
#	('REDIRECT',<URL>)
#	   - everything worked well, but instead of a page body, the user
#		 should be redirected (usually in the case of processing form
#		 input)
#
#	'IMAGE' and 'SVG' are also valid results. 


sub getPageBody {
	return ('ERROR',undef);
}

sub getOnLoadJS { return undef };  # Default

sub getMenuBuilder {
	my $self = shift;

	my $menu_builder;
	
	unless ($self->{_popup} or $self->{_nomenu}) {
		$menu_builder = new OME::Web::DefaultMenuBuilder ($self);
	}

	return $menu_builder;
}

sub getHeaderBuilder {
	my $self = shift;

	my $header_builder;
	
	unless ($self->{_popup} or $self->{_noheader}) {
		$header_builder = new OME::Web::DefaultHeaderBuilder;
	}

	return $header_builder;
}


# lookup(customTable, defaultTable, key)
# --------------------------------------

sub lookup {
	my $custom	= shift;
	my $default = shift;
	my $key		= shift;

	if (defined $custom->{$key}) {
	return $custom->{$key};
	} else {
	return $default->{$key};
	}
}


# combine(default, custom, ...)
# ----------------------------------

sub combine {
	#my $custom	 = shift;
	my $table;
	my %result;
	my ($key,$value);

	foreach $table (@_) {
	while (($key,$value) = each %$table)
	{
		$result{$key} = $value;
	}
	}

	return \%result;
}


# space(n)
# --------
sub space {
	my $n = shift;
	my $result = '';
	my $i;

	for ($i = 0; $i < $n; $i++)
	{
	$result .= '&nbsp;';
	}

	return $result;
}


# font(params, ...)
# -----------------
sub font {
	my $self	= shift;
	my $CGI		= $self->{CGI};
	my $params	= shift;
	my @content = @_;

	return $CGI->font(combine($self->{fontDefaults},$params),@content);
}


# contentType
# -----------------
# Implemented the same way as Session - acessor for __contentType


# table(params, ...)
# ------------------

sub table {
	my $self	= shift;
	my $CGI		= $self->{CGI};
	my $params	= shift;
	my @content = @_;

	return $CGI->table(combine($self->{tableDefaults},$params),@content) . "\n";
}


# tableHeaders(rowParams, columnParams, ...)
# ------------------------------------------

sub tableHeaders {
	my $self	  = shift;
	my $CGI		  = $self->{CGI};
	my $rowParams = shift;
	my $colParams = shift;
	#my @content   = @_;
	my ($h,$hs);

	$hs = "";
	foreach $h (@_) {
	$hs .= $CGI->td(combine($self->{tableHeaderDefaults},$colParams),
			$self->font({color => 'WHITE'},
					$CGI->small($CGI->b(space(2).$h.space(2)))));
	$hs .= "\n";
	}
		   
	my $x = $CGI->Tr(combine($self->{tableHeaderRowDefaults},$rowParams),$hs);

	return $x . "\n";
}


# tableRow(params, ...)
# ---------------------

sub tableColoredRow {
	my $self	= shift;
	my $CGI		= $self->{CGI};
	my $params	= shift;

	my $rowColor = $self->{tableRowColors}->[$self->{nextRowColor}];
	$self->{nextRowColor} = 1 - $self->{nextRowColor};

	return $CGI->Tr(combine($self->{tableRowDefaults},{bgcolor => $rowColor},$params),@_) . "\n";
}


sub tableRow {
	my $self	= shift;
	my $CGI		= $self->{CGI};
	my $params	= shift;

	return $CGI->Tr(combine($self->{tableRowDefaults},$params),@_) . "\n";
}


# tableCell(params, ...)
# ----------------------

sub tableCell {
	my $self	= shift;
	my $CGI		= $self->{CGI};
	my $params	= shift;

	my $thisRowColor = $self->{nextRowColor};
	my $rowColor = $self->{tableRowColors}->[$thisRowColor];
	
	return $CGI->td(combine($self->{tableCellDefaults},{bgcolor => $rowColor},$params),
			$self->font({},
				space(1),
				@_,
				space(1))) . "\n";
}


# spacer(width,height)
# --------------------

sub spacer {
	my $self   = shift;
	my $CGI	   = $self->{CGI};
	my $width  = shift;
	my $height = shift;

	return $CGI->img({src => "/perl/spacer.gif", width => $width, height => $height});
}


# tableLine(width)
# ----------------

sub tableLine {
	my $self  = shift;
	my $CGI	  = $self->{CGI};
	my $width = shift;
	my $height = shift;

	my $params = {colspan => $width};
	if (defined $height) {
	$params->{height} = $height;
	}

	return $CGI->Tr($self->{tableHeaderRowDefaults},
			$CGI->td(combine($self->{tableHeaderDefaults},$params),
				 $self->spacer(1,1))) . "\n";
}

=head2 _loadTypeAndGetInfo

	my ($package_name, $common_name, $formal_name, $ST) = 
		$self->_loadTypeAndGetInfo( $type );

$type can be a DBObject name ("OME::Image"), an Attribute name
("@Pixels"), or an instance of either

Loads the package appropriately and returns descriptive information.

$package_name is the name of the DBObject package
$common_name is a name suitable for display
$formal_name is the name suitable for passing as a parameter or to functions
	(package name for standard DBObjects, @AttrName for Attributes)
$ST is the Semantic Type if $type is a ST or attribute. Otherwise it's undef.

=cut

sub _loadTypeAndGetInfo {
	my ($proto, $type) = @_;
	confess "type is undefined!" unless defined $type;
	confess "type is blank!" if $type eq '';

	my ($package_name, $common_name, $formal_name, $ST);
	
	# Set formal_name
	if( ref($type) ) {
		$formal_name = ref( $type );
	} else {
		$formal_name = $type;
	}
	$formal_name =~ s/^OME::SemanticType::__/@/;
	
	# Attribute: load Info and package
	if( $formal_name =~ /^@/ ) {
		my $session = OME::Session->instance();
		$common_name = substr( $formal_name, 1 );
		$ST = $session->Factory->findObject("OME::SemanticType", name => $common_name)
			or confess "Could not find a Semantic type with name '$common_name'";
		$ST->requireAttributeTypePackage()
			unless ref($type); # unless type is already loaded
		$package_name = $ST->getAttributeTypePackage();

	# DBObject: load info and package
	} else {
		$package_name = $formal_name;
		$package_name->require()
			or confess "Error loading package $package_name.";
		$common_name = $package_name;
		$common_name =~ s/OME:://;
		$common_name =~ s/::/ /g;
	}
	
	return ($package_name, $common_name, $formal_name, $ST);	
}

=head2 actionTemplateDir

	my $template_dir = $self->actionTemplateDir( );
	
	Returns the directory where templates for Action layouts are stored.
	Optionally takes a 'custom' parameter that returns the path 
	to the custom template Action directory.

=cut

sub actionTemplateDir { 
	my $self = shift;
	my $custom = shift;
	my $session = $self->Session();
	my $tmpl_dir = $self->Session()->Configuration()->template_dir();
	if( $custom ) {
		return $tmpl_dir."/Actions/";
	} else {
		return $tmpl_dir."/System/Actions/";
	}
}

=head2 rootTemplateDir

	my $template_dir = $self->rootTemplateDir( );
	
	Returns the directory where templates for layouts are stored.
	Optionally takes a 'custom' parameter that returns the path 
	to the custom template directory.

=cut

sub rootTemplateDir { 
	my $self = shift;
	my $custom = shift;
	my $session = $self->Session();
	my $tmpl_dir = $self->Session()->Configuration()->template_dir();
	if( $custom ) {
		return $tmpl_dir;
	} else {
		return $tmpl_dir."/System/";
	}
}



=head2 getObjDetailURL

	my $url_to_obj_detail = $self->getObjDetailURL( $obj, %url_params );

$obj should be a DBObject instance. Attributes are fine.
%url_params is optional. If specified, it should contain a list of URL
parameters such as ( Popup => 1 ).

returns a url to a detailed view of the object

=cut

sub getObjDetailURL {
	my ($self, $obj, %url_params) = @_;
	my $formal_name = $obj->getFormalName();

	return $self->pageURL( 'OME::Web::DBObjDetail', { 
		Type => $formal_name,
		ID   => $obj->id(),
		( (ref( $self ) )&& ( exists $self->{_popup} ) && ( $self->{_popup} ) ?
			( Popup => 1 ) :
			()
		),
		%url_params
	} );
}

=head2 getSearchAccessorURL

	my $search_url = $self->getSearchAccessorURL( $obj, $method );

$obj should be a DBObject instance. Attributes are fine.
$method should be a 'has-many' or 'many-to-many' method of $obj

returns a url to a search page for whatever is returned from $obj's $method

=cut

sub getSearchAccessorURL {
	my ($self, $obj, $method) = @_;
	$self->_loadTypeAndGetInfo( $obj->getAccessorReferenceType( $method ) );
	return $self->pageURL( 'OME::Web::Search', {
		SearchType      => $obj->getAccessorReferenceType( $method )->getFormalName(),
		accessor_type   => $obj->getFormalName(),
		accessor_id     => $obj->id, 
		accessor_method => $method
	} );
}

=head2 getSearchURL

	my $search_url = $self->getSearchURL( $obj_type, @search_params );

same input parameters as $factory->findObjects()

returns a url to a search page that corresponds to that kind of DB search

=cut

sub getSearchURL {
	my ($self, $obj_type, @search_params) = @_;
	my ($package_name, $common_name, $formal_name, $ST) = 
		$self->_loadTypeAndGetInfo( $obj_type );
	return $self->pageURL( 'OME::Web::Search', {
		SearchType      => $formal_name, 
		@search_params
	} );
}

=head2 getDownloadAllURL
    
    my $zip_url = $self->getDownloadAllURL( $obj );

$obj should be a DBObject instance.

returns a URL to download all the image files for the object

=cut

sub getDownloadAllURL {
    my ($self, $obj) = @_;
    my $original_files = OME::Tasks::ImageManager->getImageOriginalFiles($obj);
    my $zip_url = $self->Session()->Factory()->findObject( '@Repository' )->ImageServerURL()."?Method=ZipFiles&FileID=";
    foreach my $zip_imgObj(@{$original_files}) {
	$zip_url = $zip_url.$zip_imgObj->FileID().",";
    }
    $zip_url = substr($zip_url, 0, -1);
    $zip_url = $zip_url."&OrigName=".$obj->name();
    
    return $zip_url;
}


1;

=head1 AUTHOR

Douglas Creager <dcreager@alum.mit.edu>,
Josiah Johnston <siah@nih.gov>,
Ilya Goldberg <igg@nih.gov>,
Open Microscopy Environment

=cut
