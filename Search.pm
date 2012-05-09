# OME/Web/Search.pm

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
# Written by:    Josiah Johnston <siah@nih.gov>
#
#-------------------------------------------------------------------------------


package OME::Web::Search;

=pod

=head1 NAME

OME::Web::Search

=head1 DESCRIPTION

Allow searches and selects for any DBObject or attribute.

=cut

#*********
#********* INCLUDES
#*********

use strict;
use OME;
our $VERSION = $OME::VERSION;
use Log::Agent;
use Carp;
use HTML::Template;

use base qw(OME::Web);

#*********
#********* PUBLIC METHODS
#*********

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = $class->SUPER::new(@_);
	
	# _default_limit sets the number of results per page
	$self->{ _default_limit } = 27;
	
	# _display_modes lists formats the results can be displayed in. 
	#	mode maps to a template name. 
	#	mode_title is presented to the user.
	$self->{ _display_modes } = [
		{ mode => 'tiled_list', mode_title => 'Summaries' },
		{ mode => 'tiled_ref_list', mode_title => 'Names' },
	];
	
	$self->{ form_name } = 'primary';
	
	return $self;
}

sub getMenuText {
	my $self = shift;
	my $menuText = "Other";
	return $menuText unless ref($self);

	my $q    = $self->CGI();
	my $type = $q->param( 'SearchType' );
	$type = $q->param( 'Locked_SearchType' ) unless $type;

	if( $type ) {
		my ($package_name, $common_name, $formal_name, $ST) = $self->_loadTypeAndGetInfo( $type );
		return "$common_name";
    }
	return $menuText;
}

sub getPageTitle {
	my $self = shift;
	my $menuText = "Search for something";
	return $menuText unless ref($self);
	my $q    = $self->CGI();
	my $type = $q->param( 'SearchType' );
	$type = $q->param( 'Locked_SearchType' ) unless $type;

	if( $type ) {
		my ($package_name, $common_name, $formal_name, $ST) = $self->_loadTypeAndGetInfo( $type );
    	return "Search for $common_name";
    }
	return $menuText;
}

sub getPageBody {

	#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-
	# Setup variables
	my $self = shift;	
	my $factory = $self->Session()->Factory();
	my $q    = $self->CGI();
	# $type is the formal name of type of object being searched for
	my $type = $self->_getCurrentSearchType();
	my $html = $q->startform( -name => 'primary', -action => $self->pageURL( 'OME::Web::Search' ) );
	my %tmpl_data;
	my $form_name = $self->{ form_name };


	#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-
	# Save the url-parameters if any were passed. 
	# e.g. accessor_type, accessor_id, accessor_method, select
	if( $q->param( '__save_these_params' ) ) {
		$html .= "\n".$q->hidden( -name => '__save_these_params' )."\n";
		foreach my $param ( $q->param( '__save_these_params' ) ){
			my $value = $q->param( $param );
			$q->param( $param, $value );
			$html .= $q->hidden( -name => $param )."\n";
		}
	} else {
		my %do_not_save_these_url_params = (
			'Page' => undef,
			'SearchType' => undef
		);
		my @params_to_save = grep( ( not exists $do_not_save_these_url_params{ $_ } ), $q->url_param() );
		$html .= "\n".$q->hidden( -name => '__save_these_params', -values => \@params_to_save )."\n";
		$html .= "\n".$q->hidden( -name => $_, -default => $q->param( $_ ) )."\n"
			foreach ( @params_to_save );
	}

	#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-
	# Return results of a select, then close this popup window.
	# This search package can be called as a popup window that searches & selects.
	if( $q->param( 'do_select' ) || $q->param( 'select_all' ) ) {
		my @selected_objects;
		
		# retrieve checked boxes
		if( $q->param( 'do_select' ) ) {
			my @selection    = $q->param( 'selected_objects' );
			# weed out blank selections
			@selection = grep( $_ && $_ ne '', @selection );
			# and duplicate selections
			my %unique_selection;
			$unique_selection{ $_ } = undef foreach @selection;
			@selection = keys %unique_selection;
			# convert LSIDs into objs.
			my $resolver = new OME::Tasks::LSIDManager();
			@selected_objects = map( $resolver->getObject($_), @selection );

		# retrieve all search results
		} else {
			my %searchParams = $self->_getSearchParams();
			my ($package_name, $common_name, $formal_name, $ST) = $self->_loadTypeAndGetInfo( $type );
			@selected_objects = $factory->findObjects( $formal_name, %searchParams );
 		}

		my $return_to_form = ( $q->url_param( 'return_to_form' ) || $q->param( 'return_to_form' ) || 'primary');
		my $return_to_form_element = ( $q->url_param( 'return_to' ) || $q->param( 'return_to' ) );
		my $ids = join( ',', map( $_->id, @selected_objects ) );
		$self->{ _onLoadJS } = <<END_HTML;
				window.opener.document.forms['$return_to_form'].${return_to_form_element}.value = '$ids';
				window.opener.document.forms['$return_to_form'].submit();
				window.close();
END_HTML
		return( 'HTML', '' );
	}

	#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-
	# get a Drop down list of search types
	$tmpl_data{ search_types } = $self->__get_search_types_popup_menu();

	# set up display modes
	my $current_display_mode = ( $q->param( 'Mode' ) || 'tiled_list' );
	foreach my $entry ( @{ $self->{ _display_modes } } ) {
		my %mode_data = %$entry;
		$mode_data{ checked } = 'checked'
			if( $entry->{mode} eq $current_display_mode );
		push( @{ $tmpl_data{ modes_loop } }, \%mode_data );
	}
	
	# If a type is selected, write in the search fields.
	# Also search if search fields are ready.
	if( $type ) {
		my ($package_name, $common_name, $formal_name, $ST) = $self->_loadTypeAndGetInfo( $type );
		
		# finish setting template data not specific to search results
		if( $q->param( 'Locked_SearchType' ) ) {
			$tmpl_data{ Locked_SearchType } = $common_name;
			$tmpl_data{ formal_name } = $formal_name;
		}

		my $render = $self->Renderer();
		# search_type is the type that the posted search parameters are
		# meant for. It will be different than Type if the user just
		# switched what type she is looking for.
 		my $search_type = $q->param( 'search_type' );
 		# search_names stores the names of the search fields. any or
 		# all of these may posted as a cgi parameter
		my @cgi_search_names = $q->param( 'search_names' );

		# clear stale search parameters
		# Reset fields if the search type was just switched.
		unless( $search_type && $search_type eq $type || !$search_type ) {
			$q->delete( $_ ) foreach( @cgi_search_names );

 			$q->param( '__order', '' );
 			$q->param( '__offset', '' );
 			$q->param( 'search_type', $type );
 			$q->param( 'accessor_id', '');
 			$q->param('/accessor_object_ref','');
 		}
 		
		$tmpl_data{ criteria_controls } = $self->getSearchCriteria( $type );

		# Get Objects & Render them
		my ($objects, $paging_text ) = $self->search();
		my $select = ( $q->param( 'select' ) or $q->url_param( 'select' ) );
		$tmpl_data{ results } = $render->renderArray( $objects, $current_display_mode, 
			{ pager_text => $paging_text, type => $type, 
				( $select && $select eq 'many' ?
					( draw_checkboxes => 1 ) :
				( $select && $select eq 'one' ?
					( draw_radiobuttons => 1 ) :
					()
				) )
			} );

		# Select button
		$tmpl_data{do_select} = 
			'<ul class="ome_quiet">'.
			'<li><a href="javascript:selectAllCheckboxes( \'selected_objects\' );">Check all boxes on this page</a></li'.
			'<li><a href="javascript:deselectAllCheckboxes( \'selected_objects\' );">Reset all boxes on this page</a></li>'.
			'</ul>'
			if( $select && $select eq 'many' );
		$tmpl_data{do_select} .= 

		    
			$q->submit( { 
				-name => 'do_select',
				-value => 'Select checked objects',
			} ) .
			$q->submit( { 
				-name => 'select_all',
				-value => 'Select all search results',
			} )
			if( $select );

		# This is used to retain selected objects across pages. 
		# It takes advantage of CGI's "sticky fields". The values (i.e. LSID's)
		# of 'selected_objects' passed in from checkboxes will make their way
		# into these hidden fields. The problem then is unselecting. If I select
		# a checkbox, and go to the next page then that value is saved as a
		# hidden field. If I come back to the first page and unselect the object,
		# the object is still stored as a hidden field, and will appear as checked
		# again if I go back and forth between pages.
		$html .= $q->hidden( -name => 'selected_objects' )
			if( $select && $select eq 'many' );


		# gotta have hidden fields
		$html .= "\n".
			# tell the form what search fields are on it and what type they are for.
			$q->hidden( -name => 'search_names' ).
			$q->hidden( -name => 'search_type', -default => $type ).
			# these are needed for paging
			$q->hidden( -name => '__order' ).
			$q->hidden( -name => '__offset' ).
			$q->hidden( -name => 'last_order_by' ).
			$q->hidden( -name => 'page_action', -default => undef, -override => 1 ).
			$q->hidden( -name => 'accessor_id');
	}
	
	my $tmpl = HTML::Template->new( 
		filename       => 'Search.tmpl', 
		path           => $self->_baseTemplateDir(),
		case_sensitive => 1 
	);
	$tmpl->param( %tmpl_data );

	$html .= 
		$tmpl->output().
		$q->endform();

	return ( 'HTML', $html );	
}

sub getOnLoadJS { return shift->{ _onLoadJS }; }

=head2 getSearchFields

	# get html form elements keyed by field names 
	my ($form_fields, $search_paths) = OME::Web::Search->getSearchFields( $type, \@field_names, \%default_search_values );

$type can be a DBObject name ("OME::Image"), an Attribute name
("@Pixels"), or an instance of either
@field_names is used to populate the returned hash.
%default_search_values is also optional. If given, it is used to populate the search form fields.

$form_fields is a hash reference of html form inputs { field_name => form_input, ... }
$search_paths is also a hash reference keyed by field names. It's values
are search paths. In most cases the search path will be the same as
the field name. For reference fields, the path will specify a field in the referent. 
For example, a reference field named 'dataset' would have a search path 'dataset.name'

=cut

sub getSearchFields {
	my ($self, $type, $field_names, $defaults) = @_;
	my ($form_fields, $search_paths);
	
	my $specializedSearch = $self->_specialize( $type );
	($form_fields, $search_paths) = $specializedSearch->_getSearchFields( $type, $field_names, $defaults )
		if( $specializedSearch and $specializedSearch->can('_getSearchFields') );

	my ($package_name, $common_name, $formal_name, $ST) =
		OME::Web->_loadTypeAndGetInfo( $type );

	my $q = $self->CGI();
	my %fieldRefs = map{ $_ => $package_name->getAccessorReferenceType( $_ ) } @$field_names;
	foreach my $field ( @$field_names ) {
		next if exists $form_fields->{ $field };
		if( $fieldRefs{ $field } ) {
			( $form_fields->{ $field }, $search_paths->{ $field } ) = 
				$self->getRefSearchField( $formal_name, $fieldRefs{ $field }, $field, $defaults->{ $field } );

		} else {
			$q->param( $field, $defaults->{ $field }  ) 
				unless defined $q->param( $field );
			$form_fields->{ $field } = $q->textfield( 
				-name    => $field , 
				-size    => 17, 
				-default => $defaults->{ $field } 
			);
			$search_paths->{ $field } = $field;
		}
	}

	return ( $form_fields, $search_paths );
}

=head2 getRefSearchField

	# get an html form element that will allow searches to $to_type
	my ( $searchField, $search_path ) = 
		$self->getRefSearchField( $from_type, $to_type, $accessor_to_type, $default_obj );

the types may be a DBObject name ("OME::Image"), an Attribute name
("@Pixels"), or an instance of either
$from_type is the type you are searching from
$accessor_to_type is an accessor of $from_type that returns an instance of $to_type
$to_type is the type the accessor returns

returns a form input and a search path for that input. The search path
for a module_execution's module field is module.name

=cut

sub getRefSearchField {
	my ($self, $from_type, $to_type, $accessor_to_type, $default) = @_;
	
	my $specializedSearch = $self->_specialize( $to_type );

	return $specializedSearch->_getRefSearchField( $from_type, $to_type, $accessor_to_type, $default )
		if( $specializedSearch and $specializedSearch->can('_getRefSearchField') );
	
	my (undef, undef, $from_formal_name) = OME::Web->_loadTypeAndGetInfo( $from_type );
	my ($to_package) = OME::Web->_loadTypeAndGetInfo( $to_type );
	my $searchOn = '';
	if( $to_package->getColumnType( 'name' ) ) {
		$searchOn = '.name';
		$default = $default->name() if $default;
	} elsif( $to_package->getColumnType( 'Name' ) ) {
		$searchOn = '.Name';
		$default = $default->Name() if $default;
	} else {
		$default = $default->id() if $default;
	}

	my $q = $self->CGI();
	$q->param( $accessor_to_type.$searchOn, $default  ) 
		unless defined $q->param($accessor_to_type.$searchOn );
	return ( 
		$q->textfield( -name => $accessor_to_type.$searchOn , -size => 17, -default => $default ),
		$accessor_to_type.$searchOn,
		$default
	);
}

=head1 Internal Methods

These methods should not be accessed from outside the class

=cut 

sub getSearchCriteria {
	my ($self, $type)    = @_;
	my $q                = $self->CGI();
	my @cgi_search_names = $q->param( 'search_names' );
	my $render = $self->Renderer();
	my $factory = $self->Session()->Factory();
	my %tmpl_data;

	my ($package_name, $common_name, $formal_name, $ST) =
		$self->_loadTypeAndGetInfo( $type );
	my $form_name = $self->{ form_name };

	my $tmpl_path = $self->_findTemplate( $type );
	my $tmpl = HTML::Template->new( filename => $tmpl_path,
	                                case_sensitive => 1 );

	
	# Setting up Advanced Searching
	$tmpl_data{ '/adv_search_setup' } = $self->_setupAdvancedSearch();
	
	# accessor stuff. 
	if( $q->param( 'accessor_id' ) && $q->param( 'accessor_id' ) ne '' ) {
	# We are working in accessor mode. Set object reference
		my $typeToAccessFrom = $q->param( 'accessor_type' );
		my $idToAccessFrom   = $q->param( 'accessor_id' );
		my $accessorMethod   = $q->param( 'accessor_method' );
		my $objectToAccessFrom = $factory->
			loadObject( $typeToAccessFrom, $idToAccessFrom )
			or die "Could not load $typeToAccessFrom, id = $idToAccessFrom";
		$tmpl_data{ '/accessor_object_ref' } = $render->render( $objectToAccessFrom, 'ref' ).
			"(<a href='javascript: document.forms[\"$form_name\"].elements[\"accessor_id\"].value = \"\"; ".
			                     "document.forms[\"$form_name\"].submit();'".
			   "title='Cancel selection'/>X</a> ".
			"<a href='javascript: selectOne( \"$typeToAccessFrom\", \"accessor_id\" );'".
			   "title='Change selection'/>C</a>)";
	}
	
	# Acquire search fields
	my @search_fields;

	if( $tmpl->query( name => '/search_fields_loop' ) ) {
	# Query the object for its fields
		@search_fields = ($render->getFields( $type, 'summary' ), 'id' );
	} else {
	# Otherwise, the search fields are in the template.
		@search_fields = grep( (!m/^\//), $tmpl->param() ); # Screen out special field requests that start with '/'
	}

	my ($form_fields, $search_paths) = $self->getSearchFields( $type, \@search_fields );
	my %field_titles = $render->getFieldTitles( $type, \@search_fields );
	$q->param( 'search_names', values %$search_paths); # explicitly record what fields we are searching on.
	my $specializedSearch = $self->_specialize( $type );
	my $order = ( $specializedSearch ?
		$specializedSearch->__sort_field( $search_paths, $search_paths->{ $search_fields[0] }) :
		$self->__sort_field( $search_paths, $search_paths->{ $search_fields[0] })
	);
	
	# Render search fields
	my $search_field_tmpl = HTML::Template->new( 
		filename       => 'search_field.tmpl',
		path           => $self->_baseTemplateDir(), 
		case_sensitive => 1
	);
	foreach my $field( @search_fields ) {
		# a button for ascending sort
		my $sort_up = "<a href='javascript: document.forms[\"$form_name\"].elements[\"__order\"].value = \"".
			$search_paths->{ $field }.
  			"\"; document.forms[\"$form_name\"].submit();' title='Sort results by ".
			$field_titles{ $field }." in increasing order'".
			( $order && $order eq $search_paths->{ $field } ?
				" class = 'ome_active_sort_arrow'" : ''
			).'>';
		# a button for descending sort
		my $sort_down = "<a href='javascript: ".
				"document.forms[\"$form_name\"].elements[\"__order\"].value = ".
				"\"!".$search_paths->{ $field }."\";".
				"document.forms[\"$form_name\"].submit();' title='Sort results by ".
			$field_titles{ $field }." in decreasing order'".
			# $order is prefixed by a ! for descending sort. that explains substr().
			( $order && substr( $order, 1 ) eq $search_paths->{ $field } ?
				" class = 'ome_active_sort_arrow'" : ''
			).'>';

		$search_field_tmpl->param(
			field_label  => $field_titles{ $field },
			form_field   => $form_fields->{ $field },
			sort_up      => $sort_up, 
			sort_down    => $sort_down,
		);
		if( $tmpl->query( name => '/search_fields_loop' ) ) {
			push( 
				@{ $tmpl_data{ '/search_fields_loop' } }, 
				{ search_field => $search_field_tmpl->output() }
			) if $form_fields->{ $field };
		} else {
			$tmpl_data{$field} = $search_field_tmpl->output();
		} 
		$search_field_tmpl->clear_params();
	}

	$tmpl->param( %tmpl_data );
	return $tmpl->output();
}

sub search {
	my ($self ) = @_;
	my $q       = $self->CGI();
	my $factory = $self->Session()->Factory();

	my %searchParams = $self->_getSearchParams();
	my $pagingText;
	($pagingText, %searchParams) = $self->_preparePaging( %searchParams );
	my ($objectToAccessFrom, $accessorMethod) = $self->_prepAccessorSearch();

	my @objects;
 	if( $objectToAccessFrom ) {  	    # get objects from an accessor method
#		logdbg "debug", "Retrieving object from an accessor method:\n\t". $objectToAccessFrom->getFormalName()."(id=".$objectToAccessFrom->id.")->$accessorMethod ( ". join( ', ', map( $_." => ".$searchParams{ $_ }, keys %searchParams ) )." )";
 		@objects = $objectToAccessFrom->$accessorMethod( %searchParams );
 	} else {                            # or with factory
		my $type = $self->_getCurrentSearchType();
		my (undef, undef, $formal_name) = $self->_loadTypeAndGetInfo( $type );
# 		logdbg "debug", "Retrieving object from search parameters:\n\tfactory->findObjectsLike( $formal_name, ".join( ', ', map( $_." => ".$searchParams{ $_ }, keys %searchParams ) )." )";

		# Basic search across all fields
		if ( $searchParams{all_fields} ) {
		    my @search_names = $q->param( 'search_names' );
		    my %indivSP = %searchParams;
		    
		    delete $indivSP{all_fields};
		    
		    foreach my $search_on ( @search_names ) {
			# The hash doesn't already have the search parameter
			if (!$indivSP {$search_on} ) {
			    $indivSP{ $search_on } = $searchParams{ all_fields };
			    push @objects, $factory->findObjects( $formal_name, %indivSP );
			    delete $indivSP{ $search_on };
			}
		    }
		}		
		# Advanced search    
		else {
		    @objects = $factory->findObjects( $formal_name, %searchParams );
		}
	}
			
	return ( \@objects, $pagingText );
}


=head2 _getSearchParams

	my %searchParameters = $self->_getSearchParams();
	my $searchType       = $self->_getCurrentSearchType();
	my @objects          = $factory->findObjects( $searchType, %searchParameters );
	
	parses the search parameters from cgi parameters, and makes them ready for 
	a standard factory search. Does not include offset or limit.

=cut

sub _getSearchParams {
	my ($self ) = @_;
	my $q       = $self->CGI();
	my $factory = $self->Session()->Factory();

	my %searchParams;

	my $type = $self->_getCurrentSearchType();
	my @search_names = $q->param( 'search_names' );

	# Search From Homepage
	if ($q->param('FromPage') && $q->param('FromPage') eq 'Home') {
	    $searchParams{ owner } = [ 'ilike' , $q->param('owner')];
	    $searchParams{ all_fields } = [ 'ilike','%'.$q->param( 'all_fields' ).'%'];
	}
	# Basic Search
	elsif (!$q->param('adv_switch') && $q->param('all_fields')) {
	    $searchParams{ all_fields } = [ 'ilike','%'.$q->param( 'all_fields' ).'%'];
	}
	# Advanced Search
	else {
	    foreach my $search_on ( @search_names ) {
		next unless ( $q->param( $search_on ) && $q->param( $search_on ) ne '');
		
		my $value = $q->param( $search_on );
		
		unless( $value =~ m/,/ ) {
		    # Modifying value to make both ends wildcards, when adding search string
		    $searchParams{ $search_on } = [ 'ilike','%'.$value.'%'];
		} else {
		    $searchParams{ $search_on } = [ 'in', [ split( m/,/, $value ) ] ];
		}
	    }
	}

	return %searchParams;
}

=head2 _prepAccessorSearch

	my ($objectToAccessFrom, $accessorMethod) = $self->_prepAccessorSearch();
	
	parses the search parameters from cgi parameters, to find the object
	to search through for an accessor search mode. Used to search through
	has-many relationships.

=cut

sub _prepAccessorSearch {
	my ($self) = @_;
	my $q       = $self->CGI();
	my $factory = $self->Session()->Factory();
	
	my ($objectToAccessFrom, $accessorMethod);
	if( $q->param( 'accessor_id' ) && $q->param( 'accessor_id' ) ne ''  ) {
		my $typeToAccessFrom = $q->param( 'accessor_type' );
		my $idToAccessFrom   = $q->param( 'accessor_id' );	
	$accessorMethod   = $q->param( 'accessor_method' );
 		$objectToAccessFrom = $factory->loadObject( $typeToAccessFrom, $idToAccessFrom )
 			or die "Could not load $typeToAccessFrom, id = $idToAccessFrom";
	}
	return ($objectToAccessFrom, $accessorMethod);
}

=head2 _preparePaging

	my %searchParameters = $self->_getSearchParams();
	my $pagingText;
	($pagingText, %searchParameters) = $self->_preparePaging( %searchParameters );
	my $searchType       = $self->_getCurrentSearchType();
	my @objects          = $factory->findObjects( $searchType, %searchParameters );
	
	parses the offset or limit from incoming cgi parameters, updates them,
	and generates the paging controls.

=cut

sub _preparePaging {
	my ($self, %searchParams ) = @_;
	my $q       = $self->CGI();
	my $factory = $self->Session()->Factory();

	# load type
	my $type         = $self->_getCurrentSearchType();
	my ($package_name, $common_name, $formal_name, $ST) = $self->_loadTypeAndGetInfo( $type );
	my ($objectToAccessFrom, $accessorMethod) = $self->_prepAccessorSearch();

	# count Objects
 	my $object_count;
	if( $objectToAccessFrom ) {
# getColumnType doesn't report on valid but as yet uninferred relations, so I'm disabling this error check for now.
# 		ref( $objectToAccessFrom )->getColumnType( $accessorMethod )
# 			or die "$accessorMethod is an unknown accessor for $typeToAccessFrom";
 		my $countAccessor = "count_".$accessorMethod;
 		$object_count = $objectToAccessFrom->$countAccessor( %searchParams );
 	} else {
	    # Basic Search
	    if ($searchParams{all_fields}) {
		$object_count = 0;
		my %indivSP;

		%indivSP = %searchParams;
		delete $indivSP{ all_fields };

		foreach my $paramKey ($q->param( 'search_names' )) {
		    if (!$indivSP{ $paramKey }) {
			$indivSP{ $paramKey } = $searchParams{all_fields};

			$object_count += $factory->countObjects( $formal_name, %indivSP );
			delete $indivSP{ $paramKey };
		    }
		}
	    }
	    # Advanced Search
	    else {
		$object_count = $factory->countObjects( $formal_name, %searchParams );
	    }
	}

	# PAGING: prepare limit, offset, and order_by
	$searchParams{ __limit } = $self->{ _default_limit };
	my $numPages = POSIX::ceil( $object_count / $searchParams{ __limit } );
	$searchParams{ __order } = $self->__sort_field();
	# only use the offset parameter if we're ordering by the same thing as last time
	if( defined $q->param( 'last_order_by') && 
	    $q->param( 'last_order_by') eq $searchParams{ __order } &&
	    $q->param( "__offset" ) ne '') {
		$searchParams{ __offset } = $q->param( "__offset" );
	} else {
		$searchParams{ __offset } = 0;
	}

	# Turn pages
	my $currentPage = int( $searchParams{ __offset } / $searchParams{ __limit } );
	my $action = $q->param( 'page_action' ) ;
	if( $action ) {
		my $max_offset = ($numPages - 1) * $searchParams{ __limit };
		if( $action eq 'FirstPage' ) {
			$searchParams{ __offset } = 0;
		} elsif( $action eq 'PrevPage' ) {
			$searchParams{ __offset } = ( $currentPage - 1 ) * $searchParams{ __limit };
			# paranoid check
			$searchParams{ __offset } = 0
				if $searchParams{ __offset } < 0;
		} elsif( $action eq 'NextPage' ) {
			$searchParams{ __offset } = ( $currentPage + 1 ) * $searchParams{ __limit };
			# paranoid check
			$searchParams{ __offset } = $max_offset
				if $searchParams{ __offset } > $max_offset;
		} elsif( $action eq 'LastPage' ) {
			$searchParams{ __offset } = $max_offset;
		}
	}
	# update last_order_by. don't add a key to searchParams by accident in the process.
	$q->param( 'last_order_by', (
			exists $searchParams{ __order } ?
			$searchParams{ __order } :
			undef
		) );
	# update the __offset parameter
	$q->param( "__offset", $searchParams{ __offset } );
	
	# paging controls
	my $pagingText;
	my $form_name = $self->{ form_name };
	if( $searchParams{ __limit } ) {
		my $offset = $searchParams{ __offset };
		my $limit  = $searchParams{ __limit };
		# add 1 to make it human readable (i.e. 1-n instead of 0-(n-1) )
		$currentPage = int( $searchParams{ __offset } / $searchParams{ __limit } ) + 1;
		if( $numPages > 1 ) {
			$pagingText .= $q->a( {
					-title => "First Page",
					-href => "javascript: document.forms['$form_name'].page_action.value='FirstPage'; document.forms['$form_name'].submit();",
					}, 
					'<<',
				).' '
				if ( $currentPage > 1 and $numPages > 2 );
			$pagingText .= $q->a( {
					-title => "Previous Page",
					-href => "javascript: document.forms['$form_name'].page_action.value='PrevPage'; document.forms['$form_name'].submit();",
					}, 
					'<'
				)." "
				if $currentPage > 1;
			$pagingText .= sprintf( "%u of %u ", $currentPage, $numPages);
			$pagingText .= "\n".$q->a( {
					-title => "Next Page",
					-href  => "javascript: document.forms['$form_name'].page_action.value='NextPage'; document.forms['$form_name'].submit();",
					}, 
					'>'
				)." "
				if $currentPage < $numPages;
			$pagingText .= "\n".$q->a( {
					-title => "Last Page",
					-href  => "javascript: document.forms['$form_name'].page_action.value='LastPage'; document.forms['$form_name'].submit();",
					}, 
					'>>'
				)
				if( $currentPage < $numPages and $numPages > 2 );
		}
	}

	return ($pagingText, %searchParams);
}

=head2
    
    my $advancedSearchText = $self->_setupAdvancedSearch();

    Produces text required to seperate basic searches from advanced searches.  
    This text goes before the search criteria for the type of item, most likely
    through a HTML::Template.  

=cut

sub _setupAdvancedSearch {
    my ($self) = @_;
    my $q = $self->CGI();

    my %tmpl_data;

    $tmpl_data{'/all_fields'} = $q->textfield( -name => 'all_fields', -size => 17, -default => $q->param('all_fields'));
    
    # Advanced Search
    if ($q->param('adv_switch') eq 'on') {
	$tmpl_data{'/adv_switch'} = 'checked';
	$tmpl_data{'/basic_box'} = 'hidden';
	$tmpl_data{'/adv_box'} = 'visible';
    }
    
    # Basic Search
    else {
	$tmpl_data{'/adv_switch'} = 'unchecked';
	$tmpl_data{'/basic_box'} = 'visible';
	$tmpl_data{'/adv_box'} = 'hidden';
    }
	
    my $tmpl = HTML::Template->new( 
	       filename       => 'adv_search_setup.tmpl',
	       path           => $self->_baseTemplateDir(), 
	       case_sensitive => 1
    );

    $tmpl->param( %tmpl_data );
    return $tmpl->output();
}

=head2 __sort_field

	# get the field to sort by. set a default if there isn't a cgi param
	my $order = $self->__sort_field( $search_paths, $default );
	# retrieve the order from a cgi parameter
	$searchParams{ __order } = $self->__sort_field();

	This method determines what search path the results should be ordered by.
	As a side affect, it stores the search path as a cgi parameter.
	The search path is returned.

	$default will be used if no cgi __order parameter is found, and
	there is no 'Name' or 'name' field in $search_paths
	$search_paths is a hash that is keyed by available search field
	names. It's values are search paths for each of those fields. see
	getSearchFields()

=cut

sub __sort_field {
	my ($self, $search_paths, $default ) = @_;
	my $q = $self->CGI();

	if( $q->param( '__order' ) && $q->param( '__order' ) ne '' ) {
		return $q->param( '__order' );
	}
	
	if( exists $search_paths->{ 'name' } ) {
		$q->param( '__order', $search_paths->{ 'name' } );
		return $search_paths->{ 'name' };
	} elsif( exists $search_paths->{ 'Name' } ) {
		$q->param( '__order', $search_paths->{ 'Name' } );
		return $search_paths->{ 'Name' };
	} else {
		$q->param( '__order', $default );
		return $default;
	}
}

=head2 _baseTemplateDir

	my $template_dir = $self->_baseTemplateDir();
	
	Returns the directory where specialized templates for this class are stored.

=cut

sub _baseTemplateDir { 
	my $self = shift;
	my $tmpl_dir = $self->Session()->Configuration()->template_dir();
	return $tmpl_dir."/System/Search/";
}

=head2 _findTemplate

	my $template_path = $self->_findTemplate( $obj );

returns a path to a custom template (see HTML::Template) for this $obj
and $mode - OR - undef if no matching template can be found

=cut

sub _findTemplate {
	my ( $self, $obj ) = @_;
	my $mode = 'search';
	return undef unless $obj;
	my $tmpl_dir = $self->_baseTemplateDir();
	my ($package_name, $common_name, $formal_name, $ST) =
		$self->_loadTypeAndGetInfo( $obj );
	my $tmpl_path = $formal_name; 
	$tmpl_path =~ s/@//g; 
	$tmpl_path =~ s/::/\//g; 
	$tmpl_path .= "/".$mode.".tmpl";
	$tmpl_path = $tmpl_dir.'/'.$tmpl_path;
	return $tmpl_path if -e $tmpl_path;
	$tmpl_path = $tmpl_dir.'/generic_search.tmpl';
	die "could not find a search template"
		unless -e $tmpl_path;
	return $tmpl_path;
}

=head2 _specialize

	my $specializedClass = $self->_specialize($type);

$type can be a DBObject name ("OME::Image"), an Attribute name
("@Pixels"), or an instance of either

returns a specialized prototype (if one exists) for rendering a
particular type of data.
returns undef if a specialized prototype does not exist or if it was
called from a specialized prototype.

=cut

sub _specialize {
	my ($self,$type) = @_;

	# get DBObject prototype or ST name from instance
	my ($package_name, $common_name, $formal_name, $ST) =
		$self->_loadTypeAndGetInfo( $type );
	
	# construct specialized package name
	my $specializedPackage = $formal_name;
	($specializedPackage =~ s/::/_/g or $specializedPackage =~ s/@//);
	$specializedPackage = "OME::Web::Search::".$specializedPackage;

	return $self if( ref( $self ) eq $specializedPackage );
	# return cached renderer
	return $self->{ $specializedPackage } if $self->{ $specializedPackage };

	# load specialized package
	eval( "use $specializedPackage" );
	unless( $@ ) {
		$self->{ $specializedPackage } = $specializedPackage->new( CGI => $self->CGI() );
		return $self->{ $specializedPackage };
	}
	
	# couldn't load the special package? return undef
	return undef;
}

=head2 _getCurrentSearchType

	my $searchType = $self->_getCurrentSearchType();

This loads the current search type from incoming cgi parameters.

=cut

sub _getCurrentSearchType {
	my ($self) = @_;
	my $q    = $self->CGI();
	# $type is the formal name of type of object being searched for
	my $type = $q->param( 'SearchType' ) || $q->param( 'Locked_SearchType' );
	return $type;	
}

# These routines allow filtering of search types.
sub __get_search_types {
	return (
		'OME::Project', 
		'OME::Dataset', 
		'OME::Image', 
		'OME::ModuleExecution', 
		'OME::Module', 
		'OME::AnalysisChain', 
		'OME::AnalysisChainExecution',
		'OME::SemanticType'
	);
}

=head2 __get_search_types_popup_menu

	my $popupMenuHTML = $self->__get_search_types_popup_menu();

This returns a popup_menu form element that has all available search types.

=cut

sub __get_search_types_popup_menu {

	#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-
	# Setup variables
	my $self = shift;	
	my $factory = $self->Session()->Factory();
	my $q    = $self->CGI();
	my $searchType = $self->_getCurrentSearchType();
	my $form_name = $self->{ form_name };
	
	#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-
	# Make a Drop down list of search types
	my @search_types = $self->__get_search_types();	
	# if the type requested isn't in the list of searchable types, add it. 
	# This stores the type, which is required for paging to work.
	unshift( @search_types, $searchType )
		unless(
			( not defined $searchType ) ||               # it wasn't defined
			( $searchType =~ m/^@/ ) ||                  # we'll add it below
			( grep( $_ eq $searchType, @search_types ) ) # it's already in the list
		);
	my %search_type_labels;

	foreach my $formal_name ( @search_types ) {
		my ($package_name, $common_name, undef, $ST) = $self->_loadTypeAndGetInfo( $formal_name );
		$search_type_labels{ $formal_name } = $common_name;
	}
	my @globalSTs = $factory->findObjects( 'OME::SemanticType', 
		granularity => 'G',
		__order     => 'name'
	);
	my @datasetSTs = $factory->findObjects( 'OME::SemanticType', 
		granularity => 'D',
		__order     => 'name'
	);
	my @imageSTs = $factory->findObjects( 'OME::SemanticType', 
		granularity => 'I',
		__order     => 'name'
	);
	my @featureSTs = $factory->findObjects( 'OME::SemanticType', 
		granularity => 'F',
		__order     => 'name'
	);
	
	return $q->popup_menu(
		-name     => 'SearchType',
		'-values' => [ 
			'', 
			@search_types, 
			'G', 
			map( '@'.$_->name(), @globalSTs),
			'D',
			map( '@'.$_->name(), @datasetSTs),
			'I',
			map( '@'.$_->name(), @imageSTs),
			'F',
			map( '@'.$_->name(), @featureSTs),
		],
		-default  => ( $searchType ? $searchType : '' ),
		-override => 1,
		-labels   => { 
			''  => '-- Select a Search Type --', 
			%search_type_labels,
			'G' => '-- Global Semantic Types --', 
			(map{ '@'.$_->name() => $_->name() } @globalSTs ),
			'D' => '-- Dataset Semantic Types --',
			(map{ '@'.$_->name() => $_->name() } @datasetSTs ),
			'I' => '-- Image Semantic Types --',
			(map{ '@'.$_->name() => $_->name() } @imageSTs ),
			'F' => '-- Feature Semantic Types --',
			(map{ '@'.$_->name() => $_->name() } @featureSTs ),
		},
		-onchange => "if(this.value != '' && this.value != 'G' && this.value != 'D' && this.value != 'I' && this.value != 'F' ) { document.forms['$form_name'].submit(); } return false;"
	);

}


=head1 Author

Josiah Johnston <siah@nih.gov>

=cut

1;
