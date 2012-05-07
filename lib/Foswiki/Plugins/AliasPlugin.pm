# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2003 Othello Maurer <maurer@nats.informatik.uni-hamburg.de>
# Copyright (C) 2003-2011 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at 
# http://www.gnu.org/copyleft/gpl.html
###############################################################################
package Foswiki::Plugins::AliasPlugin;    # change the package name and $pluginName!!!

use strict;
use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Attrs ();

# Foswiki maintenance
our $VERSION = '$Rev$';
our $RELEASE = '3.04';
our $SHORTDESCRIPTION = 'Define aliases which will be replaced with arbitrary strings automatically';
our $NO_PREFS_IN_TOPIC = 1;

use constant DEBUG => 0; # toggle me

# request variables
our $baseWeb;
our $baseTopic;

# flags
our $isInitialized;
our $aliasWikiWordsOnly;

# helper arrays
our %seenAliasWebTopics;
our %aliasRegex;
our %aliasValue;
our $TranslationToken = "\1\1";

# regexes
our $wordRegex;
our $wikiWordRegex;
our $topicRegex;
our $webRegex;
our $defaultWebNameRegex;
our $START = '(?:^|(?<=[\w\b\s\,\.\;\:\!\?\)\(]))';
our $STOP = '(?:$|(?=[\w\b\s\,\.\;\:\!\?\)\(]))';

###############################################################################
sub writeDebug {
  print STDERR "AliasPlugin - ".$_[0]."\n" if DEBUG;
}

###############################################################################
sub initPlugin {
  ($baseTopic, $baseWeb) = @_;

  # more in doInit
  $isInitialized = 0;
  %seenAliasWebTopics = ();

  Foswiki::Func::registerTagHandler('ALIAS', \&handleAlias);
  Foswiki::Func::registerTagHandler('UNALIAS', \&handleUnAlias);
  Foswiki::Func::registerTagHandler('ALIASES', \&handleAliases);

  return 1;
}

###############################################################################
sub doInit {

  return if $isInitialized;
  $isInitialized = 1;

  #writeDebug("doinit() called");

  # get plugin flags
  $aliasWikiWordsOnly = 
    Foswiki::Func::getPreferencesFlag("ALIASPLUGIN_ALIAS_WIKIWORDS_ONLY") || 0;
  
  # decide on how to match alias words
  $wikiWordRegex = $Foswiki::regex{'wikiWordRegex'};
  $topicRegex = $Foswiki::regex{'mixedAlphaNumRegex'};
  $webRegex = $Foswiki::regex{'webNameRegex'};
  $defaultWebNameRegex = $Foswiki::regex{'defaultWebNameRegex'};

  if ($aliasWikiWordsOnly) {
    $wordRegex = $wikiWordRegex;
  } else {
    $wordRegex = '\w+';
  }

  # init globals
  %aliasRegex = ();
  %aliasValue = ();

  # look for aliases in Main System web
  unless (getAliases($Foswiki::cfg{UsersWebName}, 'SiteAliases')) {
    getAliases($Foswiki::cfg{SystemWebName}, 'SiteAliases');
  }

  # look for aliases in current web
  getAliases($baseWeb, 'WebAliases');

  # look for aliases in the current topic
  getAliases($baseWeb, $baseTopic);
}

###############################################################################
sub handleAliases {
  my ($session, $params, $theTopic, $theWeb) = @_;

  #writeDebug("called handleAliases");

  doInit();

  my $theRegex = $params->{regex} || 'off';

  my $text = "<noautolink>\n";
  if ($theRegex eq 'on') {
    $text .= "| *Name* | *Regex* | *Value* |\n";
    foreach my $key (sort keys %aliasRegex) {
      my $regexText = $aliasRegex{$key};
      $regexText =~ s/([\x01-\x09\x0b\x0c\x0e-\x1f<>"&])/'&#'.ord($1).';'/ge;
      $regexText =~ s/\|/&#124;/go;
      $text .= "|<nop>$key  |$regexText  |$aliasValue{$key}  |\n";
    }
  } else {
    $text .= "| *Name* | *Value* |\n";
    foreach my $key (sort keys %aliasRegex) {
      $text .= "|<nop>$key  |$aliasValue{$key}  |\n";
    }
  }
  $text .= "</noautolink>\n";
  
  return $text;
}

###############################################################################
sub handleAlias {
  my ($session, $params, $theTopic, $theWeb) = @_;

  #writeDebug("called handleAlias");

  doInit();
  my $theKey = $params->{_DEFAULT} || $params->{name};
  my $theValue = $params->{value} || '';
  my $theRegex = $params->{regex} || '';

  if ($theKey && $theValue) {
    $theRegex =~ s/\$start/$START/g;
    $theRegex =~ s/\$stop/$STOP/g;
    addAliasPattern($theKey, $theValue, $theRegex);
    #writeDebug("handleAlias(): added alias $theKey -> $theValue");
    return "";
  }

  return inlineError("Error in %<nop>ALIAS%: need a =name= and a =value=");
}

###############################################################################
sub handleUnAlias {
  my ($session, $params, $theTopic, $theWeb) = @_;

  #writeDebug("called handleUnAlias");

  doInit();

  my $theKey = $params->{_DEFAULT} || $params->{name};

  if ($theKey) {
    delete $aliasRegex{$theKey};
    delete $aliasValue{$theKey};
  } else {
    # unalias all
    %aliasRegex = ();
    %aliasValue = ();
  }

  return '';
}

###############################################################################
sub addAliasPattern {
  my ($key, $value, $regex) = @_;

  $regex ||= '';

  #writeDebug("called addAliasPattern($key, $value, $regex)");

  if ($regex) {
    $aliasRegex{$key} = $regex;
    $aliasValue{$key} = $value;
  } else {
    $key =~ s/([\\\(\)\.\$])/\\$1/go;
    $value = getConvenientAlias($key, $value);
    $aliasRegex{$key} = '\b'.$key.'\b';
    $aliasValue{$key} = $value;
  }

  #writeDebug("aliasRegex{$key}=$aliasRegex{$key} aliasValue{$key}=$aliasValue{$key}");
}

###############################################################################
sub getConvenientAlias {
  my ($key, $value) = @_;

  #writeDebug("getConvenientAlias($key, $value) called");

  # convenience for wiki-links
  if ($value =~ /^($webRegex\.|$defaultWebNameRegex\.|#)$topicRegex/) {
    $value = "\[\[$value\]\[$key\]\]";
  }

  #writeDebug("returns '$value'");

  return $value;
}

###############################################################################
sub getAliases {
  my ($web, $topic) = @_;

  $topic ||= 'WebAliases';
  $web ||= $baseWeb;
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  writeDebug("getAliases($web, $topic)");

  # have we alread red these aliaes
  return 0 if defined $seenAliasWebTopics{"$web.$topic"};
  $seenAliasWebTopics{"$web.$topic"} = 1;

  # parse the topic containing the alias definitions
  return 0 unless Foswiki::Func::topicExists($web, $topic);

  my (undef, $text) = Foswiki::Func::readTopic($web, $topic);

  # hack: disable ADDTOHEAD and ADDTOZONE
  $text =~ s/%(ADDTO(HEAD|ZONE))/%<nop>$1/g;

  Foswiki::Func::expandCommonVariables($text, $topic, $web);

  return 1;
}

###############################################################################
sub completePageHandler {
  #my ($text, $hdr) = @_;

  return unless $_[0];

  my $query = Foswiki::Func::getCgiQuery();
  my $raw = $query->param("raw");
  return if defined $raw && $raw =~ /^(all)$/;

  # cleanup
  $_[0] =~ s/<!-- \/\/ALIAS -->//g;
  $_[0] =~ s/<!-- ALIAS:.*? -->//g;

  removeAliases($_[0]);
}

###############################################################################
sub beforeSaveHandler {
  my (undef, $topic, $web, $meta) = @_;

  doInit();
  return if $web eq $Foswiki::cfg{SystemWebName};

  # do the text
  my $text = $meta->text() || '';

  #print STDERR "beforeSave 1 - text=$text\n";

  my $removed = {};

  # remove ALIAS macros and verbatims temporarily
  my $macros = {};

  $text = takeOutBlocks($text, 'verbatim', $removed);
  $text =~ s/(%ALIAS{(.*?)}%)/takeOutAliasMacro($1, $2, $macros)/gmse;

  #print STDERR "beforeSave 2 - text=$text\n";

  insertAliases($text);

  #print STDERR "beforeSave 3 - text=$text\n";

  # put back stuff
  $text =~ s/$TranslationToken(\d+)$TranslationToken/$$macros{$1}/g;
  putBackBlocks( \$text, $removed, 'verbatim', 'verbatim' );

  # store new text
  $meta->text($text);

  #print STDERR "beforeSave 4 - text=$text\n";

  # do all formfields
  my @fields = $meta->find('FIELD');
  foreach my $field (@fields) {
    insertAliases($field->{value});
  }
}

###############################################################################
sub beforeEditHandler {
  my (undef, $topic, $web, $meta) = @_;

  return if $web eq $Foswiki::cfg{SystemWebName};

  # revert any alias before editing
  # ... from text
  my $text = $meta->text() || '';
  #print STDERR "beforeEdit 1 - text='$text'\n";

  my $removed = {};

  $text = takeOutBlocks($text, 'verbatim', $removed);
  removeAliases($text);
  putBackBlocks( \$text, $removed, 'verbatim', 'verbatim' );
  $meta->text($text);
  #print STDERR "beforeEdit 2 - text='$text'\n";

  # ... from formfields
  my @fields = $meta->find('FIELD');
  foreach my $field (@fields) {
    removeAliases($field->{value});
  }

  # SMELL: beforeEditHandler does not respect changes in the $meta object.
  # see Item1965. 

  $_[0] = $text;
}

###############################################################################
sub insertAliases {

  writeDebug("called insertAliases($_[0])");

  # first remove to prevent double-apply
  removeAliases($_[0]);
  writeDebug("... removed aliases $_[0]");

  # do the substitutions
  my @aliasKeys = keys %aliasRegex;
  foreach my $key (@aliasKeys) {
    $_[0] =~ s/($aliasRegex{$key})/<!-- ALIAS:$1 -->$aliasValue{$key}<!-- \/\/ALIAS -->/gms;
  }

  writeDebug("... finally $_[0]");
}

###############################################################################
sub removeAliases {
  return unless $_[0];

  $_[0] =~ s/<!-- ALIAS:(.*?) -->.*?<!-- \/\/ALIAS -->/$1/gms;
  $_[0] =~ s/&#60;!-- ALIAS:(.*?) --&#62;.*?&#60;!-- \/\/ALIAS --&#62;/$1/gms;
}

###############################################################################
sub takeOutAliasMacro {
  my ($text, $args, $map) = @_;

  # add these aliases to the stack
  if (defined $args) {
    my $params = new Foswiki::Attrs($args);
    handleAlias(undef, $params);
  }

  my $index = scalar(keys %$map);
  $$map{$index} = $text;
  return $TranslationToken."$index".$TranslationToken;
}

###############################################################################
# compatibility wrapper 
sub takeOutBlocks {
  my ($text, $tag, $map) = @_;

  return '' unless $text;

  return Foswiki::takeOutBlocks($text, $tag, $map) if defined &Foswiki::takeOutBlocks;
  return $Foswiki::Plugins::SESSION->renderer->takeOutBlocks($text, $tag, $map);
}

###############################################################################
# compatibility wrapper 
sub putBackBlocks {
  return Foswiki::putBackBlocks(@_) if defined &Foswiki::putBackBlocks;
  return $Foswiki::Plugins::SESSION->renderer->putBackBlocks(@_);
}

###############################################################################
sub inlineError {
  return "<div class='foswikiAlert'>$_[0]</div>";
}


1;
