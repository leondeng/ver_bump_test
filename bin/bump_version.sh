#!/bin/bash
BASE="$(cd "$(dirname "$0")"; pwd)"
source "$BASE/functions.sh"

# defaults
branch="master"
config_file="config/app.php"
bump_type=""

while getopts b:t:mdsh opt; do
  case $opt in
    b)
      branch=$OPTARG
    ;;
    t)
      bump_type=$OPTARG
    ;;
    h)
       cat << EOM
  usage: $0 [-b base_branch_name] [-t bump_type]
  options:
    -b sets the base branch name (default: $branch)
    -t bump type (will generate version automatically)

    This script updates version in config/app.php and creates the new release tag.
EOM
      exit
    ;;
  esac
done

fn_switch_branch $branch
fn_pull_all $branch

# current_version=`grep -A2 getVersion $config_file | tr '\n' ' ' | cut -d\' -f2`
current_version=$(fn_current_version)
if [ ! -z $bump_type ]
then
  new_version=`semver --increment $bump_type $current_version | tr -d '\n'`
  echo -n "New version generated: $current_version -> $new_version"
else
  echo -n "Current version is '$current_version', please enter the new version: "
  read new_version
fi

echo -n "Updating to '$new_version'... "
sed -i "s/'version' => '$current_version'/'version' => '$new_version'/" $config_file || fn_abort "Update version failed."
fn_success

echo -n "Commiting changes... "
last=$(git add $config_file && git commit -m "version bump;") || fn_abort "Couldn't commit version bump."
fn_success

# echo -ne "Clearing cache..."
# last=$(./symfony cc) || fn_abort "Couldn't clear cache."
# fn_success

release_tag="v$new_version"
fn_tag_exists $release_tag && fn_abort "Release tag '$release_tag' already exists."

echo -n "Creating the new release tag '$release_tag'... "
fn_tag $branch $release_tag
# fn_switch_branch $release_tag

echo -n "Pushing to origin... "
git push --follow-tags origin $branch &>/dev/null || fn_error "Push to origin failed."
fn_success

echo "all done"