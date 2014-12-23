#!/usr/bin/perl
# Getty Thesaurus of Geographic Names SPARQL reconciler.
# Created by Nathan Humpal. 2014-10-08
# Last update: 2014-12-23. Added comments for upload to github.
# ------------------------------------------------------------------------------------------------
# SCOPE: Ingests a tab delimited file with names and hierarchies from the TGN and outputs probable
# and possible tgn IDs along with disambiguating information.
# ------------------------------------------------------------------------------------------------
# REQUIRED Perl modules:
# Cpan modules: XML::SAX::Expat ; Text::CSV_XS
# SPARQL client library: https://github.com/swh/Perl-SPARQL-client-library
# (sparql.pm needs to be placed in Perl64\lib. Need to change sparql.pm line 48 to 
# 'my $query = uri_escape_utf8($tquery);'
# ------------------------------------------------------------------------------------------------
# Sources:
# http://www.ebi.ac.uk/rdf/querying-sparql-perl
# Original comments will be tagged with (SJ)
# (SJ) Example of querying SPARQL endpoint in Perl using
# (SJ) sparql.pm module from https://github.com/swh/Perl-SPARQL-client-library
# (SJ) Author: Simon Jupp
# (SJ) Copyright (c) 2013 EMBL - European Bioinformatics Institute
# ------------------------------------------------------------------------------------------------
# Problems:
# ·This is a fairly inflexible program that needs a specific type of tab delimited file with very
# specific make up. Changing it even for different regions will probably require quite a bit of
# tinkering.
# ·Character encoding remains a problem. Most names print fine, and search fine, but nonfatal
# errors might still crop up when the program runs. More problematically, some names still come
# back with the wrong encoding or mojibaked somewhere along the line.
# ------------------------------------------------------------------------------------------------
# I don't remember if this needs to be turned on or not...
# no warnings 'utf8';

use strict;
use sparql;

use Text::CSV_XS;

# This iterates backwards up the hierarchy from most specific to least specific. If the row that
# is being looked at doesn't have a city, then this looks to see if it has a county, then a state
# etc.
sub getQuery {
	if ($_[5] ne "") {
		my $queryName = $_[5];
		return $queryName;
	}
	elsif ($_[6] ne "") {
		my $queryName = $_[6];
		return $queryName;
	}
	elsif ($_[4] ne "") {
		my $queryName = $_[4];
		return $queryName;
	}
	elsif ($_[3] ne "") {
		my $queryName = $_[3];
		return $queryName;
	}
	elsif ($_[2] ne "") {
		my $queryName = $_[2];
		return $queryName;
	}
	elsif ($_[1] ne "") {
		my $queryName = $_[1];
		return $queryName;
	}
	else {
		my $queryName = $_[0];
		return $queryName;
	}
};

# This creates a filter for the SPARQL query using the name of the continent in the hierarchy, if
# one exists. If it's just a continent, then a filter isn't created.
sub filterTest {
	if (($_[6] ne "") || ($_[5] ne "") || ($_[4] ne "") || ($_[3] ne "") || ($_[2] ne "") || ($_[1] ne ""))
	{
		if ($_[0] !~ /;/){
			return "FILTER (regex(?parentString, \"$_[0]\"))";
		}
		else {
			return "";
		}
	}
	else
	{
		return "";
	}};

# This just plugs in URLs for known regions. I mistakenly thought that these wouldn't be part of
# the hierarchy, but that's not actually true. The regions should exist at some point in the LOD
# hierarchy because their part of alternative hierarchy. So these can probably be completely dis-
# regarded.
sub genRegionURI {
	$_[0] =~ s/;$//;
	if ($_[0] eq "Middle East") {
		return "<http://vocab.getty.edu/tgn/7001526>";
	}
	elsif ($_[0] eq "East Asia") {
		return "<http://vocab.getty.edu/tgn/7031110>";
	}
	elsif ($_[0] eq "South Asia") {
		return "<http://vocab.getty.edu/tgn/7031903>";
	}
	elsif ($_[0] eq "Southeast Asia") {
		return "<http://vocab.getty.edu/tgn/7016821>";
	}
	elsif ($_[0] eq "Southeast Asia; Malay Archipelago") {
		return "<http://vocab.getty.edu/tgn/7016821>; <http://vocab.getty.edu/tgn/7000225>";
	}
	elsif ($_[0] eq "Southeast Asia; Malay Archipelago") {
		return "<http://vocab.getty.edu/tgn/7016821>; <http://vocab.getty.edu/tgn/7000225>";
	}
	elsif ($_[0] eq "Central Asia") {
		return "<http://vocab.getty.edu/tgn/7017399>"
	}
	elsif ($_[0] eq "Southeast Asia; Malay Archipelago; South Asia; East Asia") {
		return "<http://vocab.getty.edu/tgn/7016821>; <http://vocab.getty.edu/tgn/7000225>; <http://vocab.getty.edu/tgn/7031903>; <http://vocab.getty.edu/tgn/7031110>"
	}
	elsif ($_[0] eq "Middle East; Caucasus") {
		return "<http://vocab.getty.edu/tgn/7001526>; <http://vocab.getty.edu/tgn/7016642>"
	}
	else {
		return "I don't know what this General Region is"
	}};

	
# Prompt for tab-delimited file name.
print "Tab-delimited file?";
chomp (my $tsvName = <>);
my $csv = Text::CSV_XS->new ({ sep_char => "\t", decode_utf8 => 1});
	
open(my $data, '<:encoding(UTF-8)', $tsvName) or die "Could not open $tsvName";

# The output tab-delimited file name and columns.
open(my $fn, ">name.txt");
print $fn "Row\tRow2\tRow3\tContinent\tGeneral Region\tCountry/Nation\tRegion\tState/Province\tCounty/Municipality\tCity/Place\tGeographic Feature\tURI\tLabel\tParent String\tLarger entity URI\tLarger entity English Name\tEntity type(s)\tGeneral Region URI\tLatitude\tLongitude\tActual Query\n";


# (SJ) store some useful prefixes
my $prefix =
"PREFIX gvp: <http://vocab.getty.edu/ontology#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
PREFIX tgn: <http://vocab.getty.edu/tgn/>";

# (SJ) The SPARQL endpoint to query
my $endpoint = "http://vocab.getty.edu/sparql";

# This is where the magic happens. The big loop through the file.
my $count = 0;
while (my $cityNamish = $csv->getline($data)) {
	$count++;
	# This goes through each line and defines the city, etc.
	my $continent = $cityNamish->[0];
	my $genRegion = $cityNamish->[1];
	my $country = $cityNamish->[2];
	my $region = $cityNamish->[3];
	my $state = $cityNamish->[4];
	my $county = $cityNamish->[5];	
	my $cityName = $cityNamish->[6];
	my $geofeat = $cityNamish->[7];

	# Calls on the test that determines the most specific name
	my $queryName = &getQuery($continent, $country, $region, $state, $county, $cityName);
	# Calls on the test to determine the filter name
	my $filterName = &filterTest($continent, $country, $region, $state, $county, $cityName);
	# Gets the general region URI, again, probably not necesssary.
	my $genRegionName = &genRegionURI($genRegion);
	
	# This is the loop for rows with a geographic feature. Because geographic features may not
	# contain the city or other region in their hierarchy, it's usually necessary to include both
	# the ID for the feature AND the ID for the most specific city/region. So this will query both
	if ($geofeat ne "") {
		my @geoArray = split(/; /, $geofeat);
		
		my $count2 = 0;
		for my $geoSplit (@geoArray) {
		$count2 =~ s/G//;
		$count2++;
		$count2 = "G" . $count2 ;
		$geoSplit =~ s/^\s+|\s+$//;
		$geoSplit =~ s/;//;
		$geoSplit =~ s/ \(.*\)$//;
		binmode(STDOUT, ":utf8");
		print "Searching " . $geoSplit . "\n";

		my $query =
		"Select ?ID ?Label ?parentString ?Bigger ?readBigger (group_concat(?readName ; separator = \" ; \") as ?readNames) (str(?Lat) as ?Latitude) (str(?Long) as ?Longitude)
		WHERE {
		  {?ID skos:prefLabel \"$geoSplit\"\@en.}
		  UNION
		  {?ID skos:prefLabel \"$geoSplit\".}
			?ID skos:prefLabel ?Label;
				gvp:parentString ?parentString ;
				gvp:placeType ?Type ;
				gvp:broaderPreferred ?Bigger.
			?Type skos:prefLabel ?readName.	
			?Bigger skos:prefLabel ?readBigger.
			OPTIONAL {?ID <http://xmlns.com/foaf/0.1/focus> ?TGNplace.
					  ?TGNplace <http://www.w3.org/2003/01/geo/wgs84_pos#lat> ?Lat;
								<http://www.w3.org/2003/01/geo/wgs84_pos#long> ?Long.}
			$filterName
			FILTER (langMatches(lang(?Label), \"EN\") || !langMatches(lang(?Label), \"*\"))
			FILTER (langMatches(lang(?readName), \"EN\") || !langMatches(lang(?readName), \"*\"))
			FILTER (langMatches(lang(?readBigger), \"EN\") || !langMatches(lang(?readBigger), \"*\"))}
		GROUP By ?ID ?Label ?parentString ?Bigger ?readBigger ?Lat ?Long";

		my $sparql = sparql->new();
		my $result = $sparql->query($endpoint, $prefix . $query);

		my $count3 = 0;
		for my $row (@{$result}) {
		  $count3++;
		  my $ID = $row->{'ID'};
		  my $Label = $row->{'Label'};
		  my $parentString = $row->{'parentString'};
		  my $Bigger = $row->{'Bigger'};
		  my $readBigger = $row->{'readBigger'};
		  my $readNames = $row->{'readNames'};
		  my $lat = $row->{'Latitude'};
		  my $long = $row->{'Longitude'};
		  print $fn $count . "\t" . $count2 . "\t" . $count3 . "\t" . $continent . "\t" . $genRegion . "\t" . $country . "\t" . $region . "\t" . $state . "\t" . $county . "\t" . $cityName . "\t" . $geofeat . "\t" ;
		  if (!defined($ID)) {
			print $fn  "¯\\_(ツ)_/¯\t\t\t\t\t\t" . $genRegionName . "\t\t\t(" ;
			print $fn  $geoSplit . ") \n" ;
			#print $fn $filterName . "\n" ;
			}
		  else {
			print $fn $ID . "\t" . $Label . "\t" . $parentString . "\t" . $Bigger . "\t" . $readBigger . "\t" . $readNames . "\t" . $genRegionName . "\t" . $lat . "\t" . $long . "\t(" ; 
			print $fn $geoSplit . ") \n" ;
			#print $fn $filterName . "\n" ;
			}
		}
		}
	};
	
	my @queryArray = split(/; /, $queryName);
	
	my $count2 = 0;
	for my $querySplit (@queryArray) {
	$count2++;
	$querySplit =~ s/^\s+|\s+$//;
	$querySplit =~ s/;//;
	$querySplit =~ s/ \(.*\)$//;
	binmode(STDOUT, ":utf8");
	print "Searching " . $querySplit . "\n";

	my $query =
		"Select ?ID ?Label ?parentString ?Bigger ?readBigger (group_concat(?readName ; separator = \" ; \") as ?readNames) (str(?Lat) as ?Latitude) (str(?Long) as ?Longitude)
		WHERE {
		  {?ID skos:prefLabel \"$querySplit\"\@en.}
		  UNION
		  {?ID skos:prefLabel \"$querySplit\".}
			?ID skos:prefLabel ?Label;
				gvp:parentString ?parentString ;
				gvp:placeType ?Type ;
				gvp:broaderPreferred ?Bigger.
			?Type skos:prefLabel ?readName.	
			?Bigger skos:prefLabel ?readBigger.
			OPTIONAL {?ID <http://xmlns.com/foaf/0.1/focus> ?TGNplace.
					  ?TGNplace <http://www.w3.org/2003/01/geo/wgs84_pos#lat> ?Lat;
								<http://www.w3.org/2003/01/geo/wgs84_pos#long> ?Long.}
			$filterName
			FILTER (langMatches(lang(?Label), \"EN\") || !langMatches(lang(?Label), \"*\"))
			FILTER (langMatches(lang(?readName), \"EN\") || !langMatches(lang(?readName), \"*\"))
			FILTER (langMatches(lang(?readBigger), \"EN\") || !langMatches(lang(?readBigger), \"*\"))}
		GROUP By ?ID ?Label ?parentString ?Bigger ?readBigger ?Lat ?Long";

	my $sparql = sparql->new();
	my $result = $sparql->query($endpoint, $prefix . $query);

	my $count3 = 0;
	for my $row (@{$result}) {
		  $count3++;
		  my $ID = $row->{'ID'};
		  my $Label = $row->{'Label'};
		  my $parentString = $row->{'parentString'};
		  my $Bigger = $row->{'Bigger'};
		  my $readBigger = $row->{'readBigger'};
		  my $readNames = $row->{'readNames'};
		  my $lat = $row->{'Latitude'};
		  my $long = $row->{'Longitude'};
		  print $fn $count . "\t" . $count2 . "\t" . $count3 . "\t" . $continent . "\t" . $genRegion . "\t" . $country . "\t" . $region . "\t" . $state . "\t" . $county . "\t" . $cityName . "\t" . $geofeat . "\t" ;
		  if (!defined($ID)) {
			print $fn  "¯\\_(ツ)_/¯\t\t\t\t\t\t" . $genRegionName . "\t\t\t(" ;
			print $fn $querySplit . ") \n" ;
			#print $fn $filterName . "\n" ;
			}
		  else {
			print $fn $ID . "\t" . $Label . "\t" . $parentString . "\t" . $Bigger . "\t" . $readBigger . "\t" . $readNames . "\t" . $genRegionName . "\t" . $lat . "\t" . $long . "\t(" ;
			print $fn $querySplit . ") \n" ;
			#print $fn $filterName . "\n" ;
		}
	}
	}
	};

	close $fn;


print "\nAll done! Open 'name.txt' to view results\n";
    while (<STDIN>) {
        last if ($_ =~ /^\s*$/); # Exit if it was just spaces (or just an enter)
        print "Just hit ENTER to quit";
    }
