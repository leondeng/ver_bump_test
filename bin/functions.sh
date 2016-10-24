#!/bin/bash

config_app_file="config/app.php"

config_files="composer.json
package.json
bower.json"

fn_success() {
  echo -e "\033[32mok\033[00m"
}

fn_warn() {
  echo -e "\033[34m$1\033[00m"
}

fn_error() {
  echo -e "\033[31mfailed: $1\033[00m"
}

fn_abort() {
  echo -e "\033[31mfailed: $1\033[00m"
  echo -e "Aborting."
  exit 1
}

fn_step() {
  echo -e "\033[1m$1\033[00m"
}

fn_fork() {
  local target="$2"
  local source="$1"
  if [[ -z "$target" ]]; then
    target="$1"
    source="$(fn_current_branch)"
  fi
  echo -ne "Forking branch $source to $target..."
  git branch $target $source &>/dev/null || fn_abort "Branching $source failed"
  fn_success
}

fn_branch_exists() {
  local branch=$1
  [[ "x$(git branch --no-color -a 2>/dev/null | cut -d '/' -f 3- | grep -c ^${branch}$)" = "x1" ]] && return 0
  [[ "x$(git branch --no-color -a 2>/dev/null | sed 's/ //g' | grep -c ^${branch}$)" = "x1" ]] && return 0
  return 1
}

fn_tag_exists() {
  local tag=$1
  [[ "x$(git tag -l $tag 2>/dev/null | grep -c $tag)" = "x1" ]] && return 0
  return 1
}

fn_tag() {
  local tag=$2
  local source="$(fn_current_branch)"
  git tag $tag
  fn_success
}

fn_current_branch() {
  echo $(git branch --no-color 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')
}

fn_current_version() {
  echo $(grep -A2 version $config_app_file | tr '\n' ' ' | cut -d\' -f4)
  # if [[-f "$config_app_file"]]; then
  #   echo $(grep -A2 version $config_app_file | tr '\n' ' ' | cut -d\' -f4)
  # else
  #   for config_file in $config_files do
  #     if [[-f "$config_file"]]; then
  #       echo $(grep -A0 '"version": "' $config_file | tr '\",' ' ' | cut -d\: -f2 | sed -e 's/^[[:space:]]*//')
  #       break
  #     fi
  #   done
  # fi
}

fn_switch_branch() {
  echo -ne "Switching to branch $1..."
  if [ ! -z "$2" ]; then
    git checkout $1 $2 &>/dev/null || fn_abort "Couldn't switch to branch $1."
  else
    git checkout $1 &>/dev/null || fn_abort "Couldn't switch to branch $1."
  fi
  fn_success
  fn_update_submodules
}

fn_delete_branch() {
  echo -ne "Deleting branch $1..."
  [[ "$(fn_current_branch)" = "$1" ]] && fn_abort "You need to be on a different branch to delete $1"
  git branch -D $1 || fn_abort "Couldn't delete branch $1"
  fn_success
}

fn_make_patch() {
  local source="$1"
  local target="$2"
  pfile="/tmp/fn_patch_${source//\//-}_${target//\//-}"
  git diff $source $target >$pfile 2>/dev/null || return 1

  echo $pfile;
}

fn_pull_all() {
  local branch=$1
  local origins=$(git branch --no-color --list -r */${branch} 2>/dev/null | cut -d '/' -f 1 | sed -e 's/ //g')

  for o in ${origins[@]}; do
    fn_pull $o $branch
  done
}

fn_pull() {
  local remote=$1
  local branch=$2
  local fetchlog=''

  echo -ne "Fetching ${branch} from ${remote}..."
  fetchlog=$(git fetch ${remote} ${branch} 2>&1)

  if [[ $? = 0 ]]; then
    fn_success
    fn_merge FETCH_HEAD
  else
    local success=1
    local prompt="How do you want to proceed?\r\n\
- view fetch [L]og\r\n\
- [R]etry\r\n\
- [C]ontinue\r\n\
- [A]bort"
    while [[ $success = 1 ]]; do
      echo -e $prompt
      read -s -n 1 action
      case $action in
        'l'|'L')
          echo "$fetchlog" | less
        ;;
        'r'|'R')
          fn_pull $remote $branch
          success=$?
        ;;
        'a'|'A')
          echo "Exiting..."
          exit 1
  ;;
        'c'|'C')
    echo "Moving on..."
    return 1
  ;;
      esac
    done
  fi
}

fn_merge() {
  local branch=$1
  local mergeopts=$2
  local mergelog=''
  local source=$(fn_current_branch)

  echo -ne "Merging ${branch}..."
  mergelog=$(git merge ${mergeopts} ${branch} 2>&1)

  if [[ $? = 0 ]]; then
    fn_success
  else
    fn_warn "incomplete"
    complete=1
    local prompt="How do you want to proceed?\r\n\
- view merge [L]og\r\n\
- view [S]tatus\r\n\
- launch [M]erge tool\r\n\
- [R]eset\r\n\
- [B]ack to ${source}\r\n\
- [C]ontinue\r\n\
- [A]bort"
    while [[ $complete = 1 ]]; do
      echo -e $prompt
      read -s -n 1 action
      case $action in
        'c'|'C')
    echo "Moving on..."
    return 1
  ;;
        'a'|'A')
          echo "Exiting..."
          exit 1
        ;;
        'r'|'R')
          echo -ne "Resetting to pre-merge state..."
          git reset --hard ORIG_HEAD &>/dev/null || fn_abort "Couldn't reset branch."
        ;;
        'l'|'L')
          echo "$mergelog" | less
        ;;
  's'|'S')
    git status | less
  ;;
        'b'|'B')
          fn_switch_branch $source
          exit 1
  ;;
        'm'|'M')
          echo -ne "Launching merge tool..."
          git mergetool
          if [[ $? = 0 ]]; then
            fn_success
      fn_update_submodules
            git add -u &>/dev/null || fn_abort "Adding changes failed."
            git commit -m "$(git fmt-merge-msg <.git/FETCH_HEAD)" &>/dev/null || fn_abort "Committing changes failed."
            complete=0
          else
            fn_warn "incomplete"
          fi
  ;;
      esac
    done
  fi

  fn_update_submodules
}

fn_update_submodules() {
  echo -ne "Updating submodules..."
  git submodule update --init &>/dev/null || fn_abort "Error updating submodules."
  fn_success
}
