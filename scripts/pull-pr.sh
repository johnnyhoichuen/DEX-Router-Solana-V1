#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: $0 [-n] <pr-number|pr-url>" >&2
	echo "  -n: dry run (show commands only)" >&2
	exit 1
}

DRYRUN=0
while getopts ":n" opt; do
	case "$opt" in
		n) DRYRUN=1 ;;
		*) usage ;;
	esac
done
shift $((OPTIND-1))

[[ $# -eq 1 ]] || usage
INPUT="$1"

# Determine repo origin URL and owner/repo
ORIGIN_URL=$(git config --get remote.origin.url || true)
if [[ -z "$ORIGIN_URL" ]]; then
	echo "fatal: no git remote 'origin' configured" >&2
	exit 2
fi

# Normalize origin to https form for API and git fetch
normalize_repo() {
	local url="$1"
	if [[ "$url" =~ ^git@github.com:(.+)\.git$ ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	elif [[ "$url" =~ ^https?://github.com/([^/]+/[^/]+)(\.git)?$ ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	else
		echo ""; return 1
	fi
}

REPO_PATH=$(normalize_repo "$ORIGIN_URL") || { echo "fatal: unsupported origin URL: $ORIGIN_URL" >&2; exit 3; }
OWNER="${REPO_PATH%%/*}"
REPO="${REPO_PATH##*/}"

# Parse PR number and remote info
PR_NUMBER=""
REMOTE_USER="$OWNER"
if [[ "$INPUT" =~ ^https?://github.com/([^/]+)/([^/]+)/pull/(\d+).*$ ]]; then
	REMOTE_USER="${BASH_REMATCH[1]}"
	REPO="${BASH_REMATCH[2]}"
	PR_NUMBER="${BASH_REMATCH[3]}"
elif [[ "$INPUT" =~ ^[0-9]+$ ]]; then
	PR_NUMBER="$INPUT"
else
	echo "fatal: could not parse PR identifier from '$INPUT'" >&2
	exit 4
fi

# Fallback to gh CLI if present to get head repo/user/branch; otherwise use GitHub API
HEAD_REPO="$OWNER/$REPO"
HEAD_REF=""
if command -v gh >/dev/null 2>&1; then
	set +e
	JSON=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRepositoryOwner,headRepository,headRefName 2>/dev/null)
	if [[ $? -eq 0 && -n "$JSON" ]]; then
		HEAD_REPO=$(echo "$JSON" | jq -r '.headRepositoryOwner.login + "/" + .headRepository.name')
		HEAD_REF=$(echo "$JSON" | jq -r '.headRefName')
	fi
	set -e
fi

# If still unknown, use GitHub REST API
if [[ -z "$HEAD_REF" ]]; then
	API_URL="https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER"
	JSON=$(curl -fsSL "$API_URL")
	HEAD_REPO=$(echo "$JSON" | jq -r '.head.repo.full_name')
	HEAD_REF=$(echo "$JSON" | jq -r '.head.ref')
fi

if [[ -z "$HEAD_REPO" || -z "$HEAD_REF" || "$HEAD_REPO" == "null" || "$HEAD_REF" == "null" ]]; then
	echo "fatal: unable to determine PR head repo/ref" >&2
	exit 5
fi

REMOTE_NAME="pr-${PR_NUMBER}"
BRANCH_NAME="pr/${PR_NUMBER}-${HEAD_REF//\//-}"
REMOTE_URL="https://github.com/${HEAD_REPO}.git"

run() {
	if [[ $DRYRUN -eq 1 ]]; then
		echo "+ $*"
	else
		"$@"
	fi
}

# Ensure jq and curl are available
for bin in curl jq; do
	if ! command -v "$bin" >/dev/null 2>&1; then
		echo "fatal: required tool '$bin' not found" >&2
		exit 6
	fi
done

# Add or update remote
if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
	run git remote set-url "$REMOTE_NAME" "$REMOTE_URL"
else
	run git remote add "$REMOTE_NAME" "$REMOTE_URL"
fi

# Fetch the PR head ref
run git fetch "$REMOTE_NAME" "+refs/heads/${HEAD_REF}:refs/remotes/${REMOTE_NAME}/${HEAD_REF}"

# Create/update local branch tracking the fetched ref
run git checkout -B "$BRANCH_NAME" "refs/remotes/${REMOTE_NAME}/${HEAD_REF}"

echo "Ready: checked out $BRANCH_NAME from $HEAD_REPO:$HEAD_REF (PR #$PR_NUMBER)" >&2