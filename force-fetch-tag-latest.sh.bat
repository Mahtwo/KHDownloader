: # Shell script for (ba)sh and cmd
: # This will automatically force fetch tag latest when doing any git fetch
: # Without this, git won't move a previously fetched tag latest to its new commit
: # The syntax "set --value=..." makes it so the config replace itself (so nothing changes) if already present
git config set --local --value="+refs/tags/latest:refs/tags/latest" --fixed-value "remote.origin.fetch" "+refs/tags/latest:refs/tags/latest"
