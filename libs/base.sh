#!/usr/bin/env bash

# ${1} directory full path
function makeEmptyDirectoryAndEnter() {
  if [ -d "${1}" ]; then
      rm -rf ${1}
  fi

  mkdir -p ${1}

  cd ${1}
}

# ${1} directory full path
function removeDirectory() {
  if [ -d "${1}" ]; then
      rm -rf ${1}
  fi
}

# ${1} file full path
function removeFile() {
  if [ -f "${1}" ]; then
      rm -f ${1}
  fi
}

# ${1} file full path
# ${2} file content
function forceWriteFile() {
  removeFile ${1}
  echo "${2}" > ${1}
}

# ${1} remote ip or hostname
# ${2} remote user
# ${3} remote password (for ssh only)
# ${4} remote command
# ${5} remote command password if command needs
function runRemoteCommand() {
  local op
  if [ "${2}" == "root" ]; then
    op="#"
  else
    op="\\\\\$"
  fi

  /usr/bin/expect <<EOF
set timeout 300
spawn ssh ${2}@${1}
expect {
  "password:" { send "${3}\r"}
  "Password:" { send "${3}\r"}
  "yes/no" {  send "yes\r"; exp_continue }
}

expect "*${2}@*\]${op}"
send "${4} \r"

expect {
  "password:" { send "${5}\r"; exp_continue }
  "Password:" { send "${5}\r"; exp_continue }
  "*${2}@*\]${op}" {  send "logout\r"}
}

EOF
  echo
}

# ${1} remote ip or hostname
# ${2} remote user
# ${3} remote password
# ${4} local file path
# ${5} remote file path
function copyRemoteFile() {
  /usr/bin/expect <<EOF
spawn scp ${4} ${2}@${1}:${5}
expect {
  "password:" { send "${3}\r"}
  "Password:" { send "${3}\r"}
  "yes/no" {  send "yes\r"; exp_continue }
}
expect "100%"
EOF
  echo
}

# ${1} remote ip or hostname
# ${2} remote user
# ${3} remote password
# ${4} file path
# ${5} file content
function forceWriteRemoteFile() {
  forceWriteFile ~/copy_asiwniwlsnixe "${5}"
  runRemoteCommand ${1} ${2} ${3} "mkdir -p `dirname ${4}`"
  copyRemoteFile ${1} ${2} ${3} ~/copy_asiwniwlsnixe ${4}
  removeFile ~/copy_asiwniwlsnixe
}
