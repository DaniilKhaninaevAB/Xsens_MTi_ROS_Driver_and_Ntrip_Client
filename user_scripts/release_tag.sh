#!/usr/bin/env bash
set -euo pipefail

VERSION_FILE="src/xsens_mti_ros2_driver/src/xdacallback.cpp"
VERSION_PREFIX="Xsens ROS2 driver node tag (Autobrains fork): "
REMOTE="origin"

usage() {
    echo "Usage: $(basename "$0") [--dry-run|-n] <new-tag>" >&2
    echo "Example: $(basename "$0") l4_dev_v1.3.2" >&2
    exit 1
}

DRY_RUN=0
NEW_TAG=""
for arg in "$@"; do
    case "${arg}" in
        --dry-run|-n) DRY_RUN=1 ;;
        -h|--help) usage ;;
        -*) echo "Unknown option: ${arg}" >&2; usage ;;
        *)
            [[ -z "${NEW_TAG}" ]] || usage
            NEW_TAG="${arg}"
            ;;
    esac
done
[[ -n "${NEW_TAG}" ]] || usage

run() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        printf '[dry-run] '
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [[ "${DRY_RUN}" -ne 1 ]]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Error: working tree has uncommitted changes. Commit or stash them first." >&2
        git status --short >&2
        exit 1
    fi
fi

if git rev-parse --verify --quiet "refs/tags/${NEW_TAG}" >/dev/null; then
    echo "Error: tag '${NEW_TAG}' already exists locally." >&2
    exit 1
fi
if git ls-remote --tags --exit-code "${REMOTE}" "refs/tags/${NEW_TAG}" >/dev/null 2>&1; then
    echo "Error: tag '${NEW_TAG}' already exists on ${REMOTE}." >&2
    exit 1
fi

if ! grep -q "${VERSION_PREFIX}" "${VERSION_FILE}"; then
    echo "Error: version line not found in ${VERSION_FILE}." >&2
    exit 1
fi

# In dry-run, snapshot the version file and restore it byte-for-byte on exit.
# This lets the dry-run preview the edit without depending on the working tree
# being clean, and without clobbering any pre-existing uncommitted edits.
if [[ "${DRY_RUN}" -eq 1 ]]; then
    BACKUP_FILE="$(mktemp)"
    cp -- "${VERSION_FILE}" "${BACKUP_FILE}"
    trap 'mv -- "${BACKUP_FILE}" "${VERSION_FILE}"' EXIT
fi

ESCAPED_PREFIX="$(printf '%s' "${VERSION_PREFIX}" | sed 's/[^A-Za-z0-9 _-]/\\&/g')"
sed -i -E "s|(${ESCAPED_PREFIX})[^\"]*|\1${NEW_TAG}|" "${VERSION_FILE}"

if ! grep -qF "${VERSION_PREFIX}${NEW_TAG}" "${VERSION_FILE}"; then
    echo "Error: failed to update version line in ${VERSION_FILE}." >&2
    if [[ "${DRY_RUN}" -ne 1 ]]; then
        git checkout -- "${VERSION_FILE}"
    fi
    exit 1
fi

echo "Pending change to ${VERSION_FILE}:"
git --no-pager diff -- "${VERSION_FILE}"
echo

CURRENT_BRANCH="$(git symbolic-ref --short -q HEAD || true)"
if [[ -z "${CURRENT_BRANCH}" ]]; then
    echo "Warning: HEAD is detached. The new commit will not be on any branch;"
    echo "         only the tag will be pushed to ${REMOTE}."
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] Would prompt for confirmation here."
    echo "[dry-run] Planned steps:"
else
    read -r -p "Commit, tag as '${NEW_TAG}', and push to ${REMOTE}? [y/N] " reply
    case "${reply}" in
        [yY]|[yY][eE][sS]) ;;
        *)
            echo "Aborted. Reverting file changes."
            git checkout -- "${VERSION_FILE}"
            exit 1
            ;;
    esac
fi

run git add "${VERSION_FILE}"
run git commit -m "Bump driver version tag to ${NEW_TAG}"
run git tag -a "${NEW_TAG}" -m "Release ${NEW_TAG}"

if [[ -n "${CURRENT_BRANCH}" ]]; then
    run git push "${REMOTE}" "${CURRENT_BRANCH}"
fi
run git push "${REMOTE}" "${NEW_TAG}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo
    echo "[dry-run] Done. No commit/tag/push was made; ${VERSION_FILE} will be restored on exit."
    echo "[dry-run] Re-run without --dry-run to apply."
else
    echo "Done. Tagged ${NEW_TAG} on $(git rev-parse --short HEAD) and pushed to ${REMOTE}."
fi
