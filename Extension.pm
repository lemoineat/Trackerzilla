# Copyright(C) 2020 Lemoine Automation Technologies
#
# This file is part of Pivotalzilla.
#
# Pivotalzilla is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Foobar is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Foobar.  If not, see <https://www.gnu.org/licenses/>.

package Bugzilla::Extension::Pivotalzilla;

use 5.10.1;
use strict;
use warnings;
use Bugzilla::Comment;
use Bugzilla::Constants;

use Data::Dumper;

use parent qw(Bugzilla::Extension);

use Bugzilla::Extension::Pivotalzilla::Util;
use Bugzilla::Extension::Pivotalzilla::Config;

our $VERSION = '0.01';

## This hook is called after the creation of a hook.
# sub bug_end_of_create {
#     my ($self, $args) = @_;
#     my $bug = $args->{bug};
#     my $id = %$bug{bug_id};
#
#     my @comments = Bugzilla::Comment->match({bug_id => $id});
#     my $commands = read_commands(\@comments, $id);
#     #if (check_create($id)){
#     #  new_pivotal_story($bug);
#     #}
# }

## This hook is called after updating a bug (creation included)
sub bug_end_of_update {
  my ($self, $args) = @_;
  my $bug = $args->{bug};
  my $id = $bug->bug_id;
  my $old_bug = $args->{old_bug};
  my $story_id = $bug->{'cf_pivotal_story_id'};

  my $comments = $bug->{added_comments};
  unless (defined $comments){
    $comments = Bugzilla::Comment->match({bug_id => $id});
    unless (scalar(@$comments) == 1){ # we assume that if there is only one comment,
      $comments = [];          # the comment is the description and the bug is new.
    }                          # else, there are just no new comments.
  }
  my $commands = read_commands($comments, $id);

  if (($bug->{bug_status} ne $old_bug->{bug_status}) && (%create_on_status{$bug->{bug_status}})){
    $commands->{create} = 1;
  }

  # If the story is already created, we don't need to create it again.
  unless ($story_id == 0){
    $commands->{create} = 0;
  }

  # Modify and post comments on bugzilla.
  foreach my $comment (@$comments){
    #$comment->remove_from_db();
  }
  my $new_comments = $commands->{new_comments};
  foreach my $comment (@$new_comments){
    Bugzilla::Comment->create({
      'thetext' => $comment->{thetext},
      'bug_id' => $id,
    });
  }

  # make sure the bug has a description
  my $all_comments = Bugzilla::Comment->match({bug_id => $id});
  unless (scalar(@$all_comments)){
    Bugzilla::Comment->create({
      'thetext' => "",
      'bug_id' => $id,
    });
    $all_comments = Bugzilla::Comment->match({bug_id => $id});
  }

  if (($story_id) || $commands->{create}){ # Hey, this doesn't work with the first story ! bad


    if ($commands->{create}){
      # Create the story.
      if (defined $changed_status_on_create{$bug->{bug_status}}){
        $bug->set_bug_status($changed_status_on_create{$bug->{bug_status}}, {});
      }
      $story_id = new_pivotal_story($bug);

      my $comment_story = "story create: https://www.pivotaltracker.com/services/v5/projects/$CONFIG{project_id}/stories/$story_id";
      $bug->add_comment(
        $comment_story,
        {
            type => CMT_NORMAL,
        }
      );
      $bug->update();

      # Post all comments
      my @comments = @$all_comments[1 .. scalar(@$all_comments)-1];
      foreach my $comment (@comments){
        my $comment_body = $comment->body;
        my $author = $comment->author->identity;
        my $text = "$comment_body\n\nFrom $author on Bugzilla";
        post_comment($story_id, $text);
      }
    }else{
      # Post new comments only
      foreach my $comment (@$new_comments){
        my $comment_body = $comment->{thetext};
        my $author = $comment->{author_};
        unless (($pivotalzibot_compatible) && ($comment_body =~ /\@bugs\b/)){
            my $text = "$comment_body\n\nFrom $author on Bugzilla";
            post_comment($story_id, $text);
        }
      }
    }

    # Update status
    if ($bug->{bug_status} ne $old_bug->{bug_status}){
      my $status;
      if (exists($satus_bugzilla_to_pivotal{$bug->{bug_status}})){
        $status = $satus_bugzilla_to_pivotal{$bug->{bug_status}};
      }else{
        $status = $default_pivotal_status;
      }
      modify_status($story_id, $status);
    }

    # Add labels
    my $labels = $commands->{labels};
    foreach my $label (@$labels){
      add_label($story_id, $label);
    }
  }

  # Remove error
  if ($commands->{clear}){
    remove_error($id);
  }

  # Add error
  my $error_comments = $commands->{error_comments};
  foreach my $comment (@$error_comments){
    Bugzilla::Comment->create($comment);
  }

  $bug->{added_comments} = [];
  if ($commands->{create}){
    $bug->update(); # save the changes in the database
  }
}

## Hook called when the db is updated (install or upgrade of bugzilla)
## Add a field cf_pivotal_story_id to the bugs.
sub install_update_db{
  my $field = new Bugzilla::Field({ name => 'cf_pivotal_story_id' });
  return if $field;

  $field = Bugzilla::Field->create({
      name        => 'pivotal_story_id',
      description => 'Story #',
      type        => FIELD_TYPE_INTEGER,        # From list in Constants.pm
      enter_bug   => 0,
      buglist     => 0,
      custom      => 1,
  });
}

sub bug_fields {
  my ($self, $args) = @_;
  my $fields = $args->{fields};
  push(@$fields, 'cf_pivotal_story_id');
}

sub bug_columns {
  my ($self, $args) = @_;
  my $columns = $args->{'columns'};
  push(@$columns, 'cf_pivotal_story_id');
}

__PACKAGE__->NAME;
