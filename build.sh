#!/bin/bash

# Fail on any error.
set -e

root=`pwd`

if [[ -z "$MJLIB_PATH" ]]; then
  # If MJLIB_PATH was not set, attempt to locate mujoco.so.
  # This grep aims to avoid nogl versions of the MuJoCo libraru.
  MJLIB_PATH=$(find -L $HOME/.mujoco/ -type f -name "*mujoco*.so" | grep "libmujoco[[:digit:]]*.so")
  if [[ ! $? ]]; then
    echo "Failed to find mujoco shared library (.so file)."
    echo "Please set MJLIB_PATH to the location of the mujoco .so file."
    exit 1
  fi
fi

if [[ ! -r "$MJLIB_PATH" ]]; then
  echo "Cannot read the mujoco library at ${MJLIB_PATH}"
  echo "Set the MJLIB_PATH env var to change this location"
  exit  1
fi

echo "MJLIB_PATH: ${MJLIB_PATH}"
export MJLIB_PATH

cmake_binary=${CMAKE_EXE:-cmake}
echo "Using cmake command '$cmake_binary'"

python_binary=${PYTHON_EXE:-python3}
echo "Using python command '$python_binary'"

tox_binary=${TOX_EXE:-$python_binary -m tox}
echo "Using tox command '$tox_binary'"

# Determine what version of Python $python_binary is.
# The extra && and || mean this will not stop the script on failure.
# python_version will be numbers and dots, e.g. 3.8.2
python_version="$($python_binary --version | grep --only-matching '[0-9.]*' 2>&1)" && exit_status=$? || exit_status=$?

# Allow the python version to be overridden.
python_version=${PYTHON_VERSION:-$python_version}

# Finally default python_version, but this should not be needed.
python_version=${python_version:-3.10}
echo "Using python version '$python_version'"

$python_binary -m pip install "setuptools"

# Install tox, which we use to build the packages.
# The packages themselves do not depend on tox.
if ! [[ -x $tox_binary ]]; then
  # tox 4 deprecates the distshare configuration parameter in tox.ini.
  # TODO(b/261983169): support tox 4.
  $python_binary -m pip install "tox < 4"
fi

echo "Recreating $root/cpp/build directory"
rm -rf "$root/cpp/build"
mkdir "$root/cpp/build"

# Build the dm_robotics.controllers package wheel.
echo "Building controllers package (setup.py) from $root/cpp"
cd "$root/cpp"
$python_binary setup.py bdist_wheel  # Uses the CMAKE_EXE environment variable.
ls "$root/cpp/dist"/dm_robotics_controllers*.whl  # Check that the wheel was built.

# We get a linux_x86_64 wheel, auditwheel repair detects and re-tags it as a
# manylinux wheel.
if which auditwheel; then
  pushd "$root/cpp/dist"
  echo "Repairing dm_robotics_controllers wheel files."
  echo "Before repairing wheel: "
  ls .
  auditwheel repair dm_robotics_controllers*.whl
  rm dm_robotics_controllers*.whl
  mv wheelhouse/* .
  rm -r wheelhouse
  echo "After repairing wheel: "
  ls .
  popd
fi

# Copy the wheel to the tox distshare directory.
echo "Copying controllers package wheel file to Tox distshare folder"
rm -rf "$root/py/dist"
mkdir "$root/py/dist"
cp "$root/cpp/dist"/dm_robotics_controllers*.whl "$root/py/dist"

echo "Building python transformations package"
cd "$root/py/transformations"
$tox_binary

echo "Building python geometry package"
cd "$root/py/geometry"
$tox_binary

echo "Building python agentflow package"
cd "$root/py/agentflow"
$tox_binary

echo "Building python moma package"
cd "$root/py/moma"
$tox_binary

echo "Building python manipulation package"
cd "$root/py/manipulation"
$tox_binary

echo "Running integration tests"
cd "$root/py/integration_test"
$tox_binary
