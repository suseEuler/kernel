#!/usr/bin/python3
# -*- coding: utf-8 -*-

import collections
import operator
import os
import os.path
import pygit2
import re
import signal
import subprocess
import sys

import exc
import git_sort
from patch import Patch
import series_conf


# https://stackoverflow.com/a/952952
flatten = lambda l: [item for sublist in l for item in sublist]


# http://stackoverflow.com/questions/1158076/implement-touch-using-python
def touch(fname, times=None):
    with open(fname, 'a'):
        os.utime(fname, times)


def libdir():
    return os.path.dirname(os.path.realpath(__file__))


def check_series():
    def check():
        return (open("series").readline().strip() ==
                "# Kernel patches configuration file")

    try:
        retval = check()
    except IOError as err:
        print("Error: could not read series file: %s" % (err,), file=sys.stderr)
        return False

    if retval:
        return True
    
    try:
        subprocess.check_output(("quilt", "--quiltrc", "-", "top",),
                                stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as err:
        if err.output.decode() == "No patches applied\n":
            pass
        else:
            raise
    if check():
        return True
    else:
        print("Error: series file does not look like series.conf. "
              "Make sure you are using the modified `quilt`; see "
              "scripts/git_sort/README.md.", file=sys.stderr)
        return False


def repo_path():
    try:
        search_path = subprocess.check_output(
            os.path.join(libdir(), "..",
                         "linux_git.sh")).decode().strip()
    except subprocess.CalledProcessError:
        print("Error: Could not determine mainline linux git repository path.",
              file=sys.stderr)
        sys.exit(1)
    return pygit2.discover_repository(search_path)


def series_header(series):
    header = []

    for line in series:
        if series_conf.filter_patches(line):
            break

        try:
            parse_section_header(line)
        except exc.KSNotFound:
            pass
        else:
            break

        header.append(line)

    return header


def series_footer(series):
    return series_header(reversed(series))


def parse_section_header(line):
    oot_text = git_sort.oot.rev
    line = line.strip()

    if not line.startswith("# "):
        raise exc.KSNotFound()
    line = line[2:]
    if line == oot_text:
        return git_sort.oot
    elif line.lower() == series_conf.start_text:
        raise exc.KSNotFound()

    words = line.split(None, 3)
    if len(words) > 2:
        raise exc.KSError(
            "Section comment \"%s\" in series.conf could not be parsed. "
            "series.conf is invalid." % (line,))
    args = [git_sort.RepoURL(words[0])]
    if len(words) == 2:
        args.append(words[1])

    head = git_sort.Head(*args)

    if head not in git_sort.remotes:
        raise exc.KSError(
            "Section comment \"%s\" in series.conf does not match any Head in "
            "variable \"remotes\". series.conf is invalid." % (line,))
    
    return head


def patches_per_section(inside_lines):
    result = collections.OrderedDict([
        (head, [],)
        for head in flatten((git_sort.remotes, (git_sort.oot,),))])

    current_head = git_sort.remotes[0]
    for line in inside_lines:
        try:
            current_head = parse_section_header(line)
        except exc.KSNotFound:
            pass

        if not series_conf.filter_patches(line):
            continue

        name = series_conf.firstword(line)
        result[current_head].append(name)

    for head, names in list(result.items()):
        if not names:
            del result[head]

    return result


def parse_inside(index, inside_lines, move_upstream):
    result = []
    for head, names in patches_per_section(inside_lines).items():
        for name in names:
            entry = InputEntry("\t%s\n" % (name,))
            entry.from_patch(index, name, head, move_upstream)
            result.append(entry)

    return result


def list_moved_patches(base_lines, remote_lines):
    base = {}
    result = []

    for head, names in patches_per_section(base_lines).items():
        for name in names:
            base[name] = head

    for head, names in patches_per_section(remote_lines).items():
        for name in names:
            if name in base and head != base[name]:
                result.append(name)

    return result


class InputEntry(object):
    commit_match = re.compile("[0-9a-f]{40}")


    def __init__(self, value):
        """
        value is typically a series.conf line but can be anything.
        """
        self.value = value


    def from_patch(self, index, name, current_head, move_upstream):
        self.name = name
        if not os.path.exists(name):
            raise exc.KSError("Could not find patch \"%s\"" % (name,))

        with Patch(open(name, mode="rb")) as patch:
            commit_tags = patch.get("Git-commit")
            repo_tags = patch.get("Git-repo")

        if not commit_tags:
            self.dest_head = git_sort.oot
            return

        class BadTag(Exception):
            pass

        def get_commit(value):
            if not value:
                raise BadTag(value)
            tag = series_conf.firstword(value)
            if not self.commit_match.match(tag):
                raise BadTag(tag)
            return tag

        try:
            self.revs = [get_commit(value) for value in commit_tags]
        except BadTag as e:
            raise exc.KSError("Git-commit tag \"%s\" in patch \"%s\" is not a "
                              "valid revision." % (e.args[0], name,))
        rev = self.revs[0]

        if len(repo_tags) > 1:
            raise exc.KSError("Multiple Git-repo tags found. Patch \"%s\" is "
                          "tagged improperly." % (name,))
        elif repo_tags:
            repo = git_sort.RepoURL(repo_tags[0])
        elif commit_tags:
            repo = git_sort.remotes[0].repo_url
        self.new_url = None

        # this is where we decide a patch line's fate in the sorted series.conf
        try:
            ic = index.lookup(rev)
        except git_sort.GSKeyError: # commit not found
            if current_head not in index.repo_heads: # repo not indexed
                if repo == current_head.repo_url: # good tag
                    self.dest_head = current_head
                else: # bad tag
                    raise exc.KSError(
                        "There is a problem with patch \"%s\". "
                        "The Git-repo tag is incorrect or the patch is in the "
                        "wrong section of series.conf and (the Git-commit tag "
                        "is incorrect or the relevant remote is outdated or "
                        "not available locally) or an entry for this "
                        "repository is missing from \"remotes\". In the last "
                        "case, please edit \"remotes\" in "
                        "\"scripts/git_sort/git_sort.py\" and commit the "
                        "result. Manual intervention is required." % (name,))
            else: # repo is indexed
                if repo == current_head.repo_url: # good tag
                    raise exc.KSError(
                        "There is a problem with patch \"%s\". "
                        "Commit \"%s\" not found in git-sort index. "
                        "The remote fetching from \"%s\" needs to be fetched "
                        "or the Git-commit tag is incorrect or the patch is "
                        "in the wrong section of series.conf. Manual "
                        "intervention is required." % (
                            name, rev, current_head.repo_url,))
                else: # bad tag
                    raise exc.KSError(
                        "There is a problem with patch \"%s\". "
                        "The Git-repo tag is incorrect or the patch is in the "
                        "wrong section of series.conf. Manual intervention is "
                        "required." % (name,))
        else: # commit found
            msg_bad_tag = "There is a problem with patch \"%s\". " \
                    "The Git-repo tag is incorrect or the patch is in " \
                    "the wrong section of series.conf. Manual " \
                    "intervention is required." % (name,)
            if current_head not in index.repo_heads: # repo not indexed
                if ic.head > current_head: # patch moved downstream
                    if repo == current_head.repo_url: # good tag
                        self.dest_head = current_head
                    else: # bad tag
                        raise exc.KSError(msg_bad_tag)
                elif ic.head == current_head: # patch didn't move
                    raise exc.KSException(
                        "Head \"%s\" is not available locally but commit "
                        "\"%s\" found in patch \"%s\" was found in that head." %
                        (ic.head, rev, name,))
                elif ic.head < current_head: # patch moved upstream
                    if move_upstream: # move patches between subsystem sections
                        self.dest_head = ic.head
                        self.dest = ic
                        if repo != ic.head.repo_url: # bad tag
                            self.new_url = ic.head.repo_url
                    else: # do not move patches between subsystem sections
                        if repo == current_head.repo_url: # good tag
                            self.dest_head = current_head
                        else: # bad tag
                            raise exc.KSError(msg_bad_tag)
            else: # repo is indexed
                if ic.head > current_head: # patch moved downstream
                    if repo == current_head.repo_url: # good tag
                        raise exc.KSError(
                            "There is a problem with patch \"%s\". "
                            "The patch is in the wrong section of series.conf "
                            "or the remote fetching from \"%s\" needs to be "
                            "fetched or the relative order of \"%s\" and "
                            "\"%s\" in \"remotes\" is incorrect. Manual "
                            "intervention is required." % (
                                name, current_head.repo_url, ic.head,
                                current_head,))
                    else: # bad tag
                        raise exc.KSError(
                            "There is a problem with patch \"%s\". "
                            "The patch is in the wrong section of series.conf "
                            "or the remote fetching from \"%s\" needs to be "
                            "fetched. Manual intervention is required." % (
                                name, current_head.repo_url,))
                elif ic.head == current_head: # patch didn't move
                    self.dest_head = ic.head
                    self.dest = ic
                    if repo != ic.head.repo_url: # bad tag
                        self.new_url = ic.head.repo_url
                elif ic.head < current_head: # patch moved upstream
                    if move_upstream: # move patches between subsystem sections
                        self.dest_head = ic.head
                        self.dest = ic
                        if repo != ic.head.repo_url: # bad tag
                            self.new_url = ic.head.repo_url
                    else: # do not move patches between subsystem sections
                        if repo == current_head.repo_url: # good tag
                            self.dest_head = current_head
                            self.dest = ic
                        else: # bad tag
                            raise exc.KSError(msg_bad_tag)


def series_sort(index, entries):
    """
    entries is a list of InputEntry objects

    Returns an OrderedDict
        result[Head][]
            series.conf line with a patch name

    Note that Head may be a "virtual head" like "out-of-tree patches".
    """
    def container(head):
        if head in index.repo_heads:
            return collections.defaultdict(list)
        else:
            return []

    result = collections.OrderedDict([
        (head, container(head),)
        for head in flatten((git_sort.remotes, (git_sort.oot,),))])

    for entry in entries:
        try:
            result[entry.dest_head][entry.dest].append(entry.value)
        except AttributeError:
            # no entry.dest
            result[entry.dest_head].append(entry.value)

    for head in index.repo_heads:
        result[head] = flatten([
            e[1]
            for e in sorted(result[head].items(), key=operator.itemgetter(0))])

    for head, lines in list(result.items()):
        if not lines:
            del result[head]

    return result


def series_format(entries):
    """
    entries is an OrderedDict
        entries[Head][]
            series.conf line with a patch name
    """
    result = []

    for head, lines in entries.items():
        if head != git_sort.remotes[0]:
            if result:
                result.append("\n")
            result.append("\t# %s\n" % (str(head),))
        result.extend(lines)

    return result


def tag_needs_update(entry):
    if entry.dest_head != git_sort.oot and entry.new_url is not None:
        return True
    else:
        return False


def update_tags(index, entries):
    for entry in entries:
        with Patch(open(entry.name, mode="r+b")) as patch:
            message = "Failed to update tag \"%s\" in patch \"%s\". This " \
                    "tag is not found."
            if entry.dest_head == git_sort.remotes[0]:
                tag_name = "Patch-mainline"
                try:
                    patch.change(tag_name, index.describe(entry.dest.index))
                except KeyError:
                    raise exc.KSNotFound(message % (tag_name, entry.name,))
                except git_sort.GSError as err:
                    raise exc.KSError("Failed to update tag \"%s\" in patch "
                                      "\"%s\". %s" % (tag_name, entry.name,
                                                      str(err),))
                patch.remove("Git-repo")
            else:
                tag_name = "Git-repo"
                try:
                    patch.change(tag_name, repr(entry.new_url))
                except KeyError:
                    raise exc.KSNotFound(message % (tag_name, entry.name,))


def sequence_insert(series, rev, top):
    """
    top is the top applied patch, None if none are applied.

    Caller must chdir to where the entries in series can be found.

    Returns the name of the new top patch and how many must be applied/popped.
    """
    git_dir = repo_path()
    repo = pygit2.Repository(git_dir)
    index = git_sort.SortIndex(repo)

    try:
        commit = str(repo.revparse_single(rev).id)
    except ValueError:
        raise exc.KSError("\"%s\" is not a valid revision." % (rev,))
    except KeyError:
        raise exc.KSError("Revision \"%s\" not found in \"%s\"." % (
            rev, git_dir,))

    marker = "# new commit"
    new_entry = InputEntry(marker)
    try:
        new_entry.dest = index.lookup(commit)
    except git_sort.GSKeyError:
        raise exc.KSError(
            "Commit %s not found in git-sort index. If it is from a "
            "repository and branch pair which is not listed in \"remotes\", "
            "please add it and submit a patch." % (commit,))
    new_entry.dest_head = new_entry.dest.head

    try:
        before, inside, after = series_conf.split(series)
    except exc.KSNotFound as err:
        raise exc.KSError(err)
    before, after = map(series_conf.filter_series, (before, after,))
    current_patches = flatten([before, series_conf.filter_series(inside), after])

    if top is None:
        top_index = 0
    else:
        top_index = current_patches.index(top) + 1

    input_entries = parse_inside(index, inside, False)
    input_entries.append(new_entry)

    sorted_entries = series_sort(index, input_entries)
    new_patches = flatten([
        before,
        [line.strip() for lines in sorted_entries.values() for line in lines],
        after,
    ])
    commit_pos = new_patches.index(marker)
    if commit_pos == 0:
        # should be inserted first in series
        name = ""
    else:
        name = new_patches[commit_pos - 1]
    del new_patches[commit_pos]

    if new_patches != current_patches:
        raise exc.KSError("Subseries is not sorted. "
                      "Please run scripts/series_sort.py.")

    return (name, commit_pos - top_index,)
