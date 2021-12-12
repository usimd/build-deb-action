#!/bin/sh

set -eu

# Usage:
#   error MESSAGE
error()
{
	echo "::error::$1"
}

# Usage:
#   end_group
end_group()
{
	echo "::endgroup::"
}

# Usage:
#   start_group GROUP_NAME
start_group()
{
	echo "::group::$1"
}

# Usage:
#   check_path_prefix PATH PREFIX
check_path_prefix()
{
	real_prefix=$(realpath "$2")
	case "$(realpath --canonicalize-missing -- "$1")" in
		"$real_prefix"|"$real_prefix/"*)
			return 0
			;;
	esac

	return 1
}

clean_up()
{
	rm --force -- "$env_file"
}

env_file=$(mktemp) || exit 1
trap clean_up EXIT INT HUP TERM

INPUT_ARTIFACTS_DIR=${INPUT_ARTIFACTS_DIR:-.}
if ! check_path_prefix "$INPUT_ARTIFACTS_DIR" "$GITHUB_WORKSPACE"; then
	error "artifacts-dir is not in GITHUB_WORKSPACE"
	exit 2
fi

INPUT_SOURCE_DIR=${INPUT_SOURCE_DIR:-.}
if ! check_path_prefix "$INPUT_SOURCE_DIR" "$GITHUB_WORKSPACE"; then
	error "source-dir is not in GITHUB_WORKSPACE"
	exit 2
fi


start_group "Preparing build container"
# Docker does not like variable values containing newlines in an --env-file, we
# will pass it separately:
env --unset=INPUT_APT_SOURCES > "$env_file"
container_id=$(docker run \
	--detach \
	--env-file="$env_file" \
	--env=GITHUB_ACTION_PATH=/github/action \
	--env=GITHUB_WORKSPACE=/github/workspace \
	--env=INPUT_APT_SOURCES \
	--rm \
	--volume="$GITHUB_ACTION_PATH":/github/action \
	--volume="$GITHUB_WORKSPACE":/github/workspace \
	--workdir=/github/workspace \
	-- "$INPUT_DOCKER_IMAGE" tail -f /dev/null \
)
end_group

start_group "Installing build dependencies"
docker exec "$container_id" /github/action/scripts/install_build_deps.sh
end_group

start_group "Building package"
docker exec "$container_id" /github/action/scripts/build_packages.sh
end_group

start_group "Moving artifacts"
docker exec "$container_id" /github/action/scripts/move_artifacts.sh
end_group

start_group "Stopping build container"
docker stop --time=1 "$container_id" >/dev/null
end_group
