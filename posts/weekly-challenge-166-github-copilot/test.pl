#!/usr/bin/env perl

use strict;
use warnings;

use Path::Tiny 'path';
use Text::Table::Tiny 'generate_table';
use List::Util 'uniq';

# create a temporary directory structure like this:
# dir_a:
my $dir_a = path('./dir_a');

# iterate over these files and directories:
# Arial.ttf  Comic_Sans.ttf  Georgia.ttf  
# Helvetica.ttf  Impact.otf  Verdana.ttf  Old_Fonts/
# create them in the temporary directory
for my $file (qw(
    Arial.ttf Comic_Sans.ttf Georgia.ttf 
    Helvetica.ttf Impact.otf Verdana.ttf
    Old_Fonts/
)) {
    $dir_a->child($file)->touchpath;
}

# dir_b:
# Arial.ttf  Comic_Sans.ttf  Courier_New.ttf  
# Helvetica.ttf  Impact.otf  Tahoma.ttf  Verdana.ttf
my $dir_b = path('./dir_b');
for my $file (qw(
    Arial.ttf Comic_Sans.ttf Courier_New.ttf 
    Helvetica.ttf Impact.otf Tahoma.ttf Verdana.ttf
)) {
    $dir_b->child($file)->touchpath;
}

# dir_c:
# Arial.ttf  Courier_New.ttf  Helvetica.ttf  
# Impact.otf  Monaco.ttf  Verdana.ttf
my $dir_c = path('./dir_c');
for my $file (qw(
    Arial.ttf Courier_New.ttf Helvetica.ttf 
    Impact.otf Monaco.ttf Verdana.ttf
)) {
    $dir_c->child($file)->touchpath;
}

# clean up the temporary directory structure at the end
# of the program
END {
    $dir_a->remove_tree;
    $dir_b->remove_tree;
    $dir_c->remove_tree;
}

# Given a few (three or more) directories (non-recursively), 
# display a side-by-side difference of files that are 
# missing from at least one of the directories. Do not 
# display files that exist in every directory.

=head2 find_missing_files(@dirs)

Takes a list of L<Path::Tiny> objects and returns a hashref 
of directories with a list of filenames that do not exist 
in all directories each.

    my $missing_files = find_missing_files(@dirs);
    # $missing_files = {
    #     dir_a => [qw(Comic_Sans.ttf Georgia.ttf Old_Fonts/)],
    #     dir_b => [qw(Comic_Sans.ttf Courier_New.ttf Tahoma.ttf)],
    #     dir_c => [qw(Courier_New.ttf Monaco.ttf)],

=cut

sub find_missing_files {
    my @dirs = @_;
    my %files_that_dont_exist_in_all_dirs_by_dir;

    # iterate directories
    # iterate files in each directory sorted by their filename
    # if the filename does not exists in all directories, add the 
    # filename to the hash of files for this directory

    for my $dir (@dirs) {
        my @files = $dir->children;
        for my $file (@files) {
            my $filename = $file->basename;
            my $exists_in_all_dirs = 1;
            for my $dir (@dirs) {
                my $file_in_dir = $dir->child($filename);
                if (!$file_in_dir->exists) {
                    $exists_in_all_dirs = 0;
                    last;
                }
            }
            if (!$exists_in_all_dirs) {
                push @{ $files_that_dont_exist_in_all_dirs_by_dir{$dir} }, $filename;
            }
        }
    }

    return \%files_that_dont_exist_in_all_dirs_by_dir;
}

my $missing_files = find_missing_files($dir_a, $dir_b, $dir_c);

=head2 make_table($missing_files_by_dir)

Takes a hashref of dirs, each containing a list of missing 
files and returns a L<Text::Table::Tiny> object.

    my $table = make_table($missing_files_by_dir);

The input data looks like this:
     
    $missing_files = {
         dir_a => [qw(Comic_Sans.ttf Georgia.ttf Old_Fonts/)],
         dir_b => [qw(Comic_Sans.ttf Courier_New.ttf Tahoma.ttf)],
         dir_c => [qw(Courier_New.ttf Monaco.ttf)],
    }

The table has one column per directory, and one row per file. The rows are 
sorted by filename. If a file is missing from a directory, the cell is empty.

    dir_a          | dir_b           | dir_c
    -------------- | --------------- | ---------------
    Comic_Sans.ttf | Comic_Sans.ttf  |
                   | Courier_New.ttf | Courier_New.ttf
    Georgia.ttf    |                 |
                   |                 | Monaco.ttf
    Old_Fonts/     |                 |
                   | Tahoma.ttf      |

=cut

sub make_table {
    my $missing_files_by_dir = shift;

    # get all unique elements of all the arrays in the hash and sort them alphabetically
    my @files_in_all_dirs = sort { $a cmp $b } uniq map { @$_ } values %$missing_files_by_dir;
    my @dirs = sort { $a cmp $b } keys %$missing_files_by_dir;

    my $table = generate_table(
        rows => [  
            [ @dirs ],
        
            # iterate the file names
            # iterate the dir for each file
            # test all file names in the dir to see if the filename exists
            # if it does, add the filename to the row
            # if it doesn't, add an empty cell to the row
            # return an array reference
            map {
                my $file = $_;
                my @row;
                for my $dir (@dirs) {
                    my $filename = $file;
                    my $dir_with_file = $missing_files_by_dir->{$dir};
                    my $exists_in_dir = grep { $_ eq $filename } @$dir_with_file;
                    push @row, $exists_in_dir ? $filename : '';
                }
                \@row;
            } @files_in_all_dirs

        ],
        header_row => 1,
    );

    return $table;
}

print make_table($missing_files);