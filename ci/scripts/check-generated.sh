#!/bin/bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Check generated files are up to date

make -k -C hw regs && git diff --exit-code
if [[ $? != 0 ]]; then
  echo -n "##vso[task.logissue type=error]"
  echo "Register headers not up-to-date. Regenerate them with 'make -C hw regs'."
  exit 1
fi

make -k -C hw top && git diff --exit-code
if [[ $? != 0 ]]; then
  echo -n "##vso[task.logissue type=error]"
  echo "Autogenerated tops not up-to-date. Regenerate with 'make -C hw top'."
  exit 1
fi

make -k -C hw otp-mmap && git diff --exit-code
if [[ $? != 0 ]]; then
  echo -n "##vso[task.logissue type=error]"
  echo "Autogenerated OTP memory map files not up-to-date. Regenerate with 'make -C hw otp-mmap'."
  exit 1
fi

make -k -C hw lc-state-enc && git diff --exit-code
if [[ $? != 0 ]]; then
  echo -n "##vso[task.logissue type=error]"
  echo "Autogenerated LC state not up-to-date. Regenerate with 'make -C hw lc-state-enc'."
  exit 1
fi

hw/ip/flash_ctrl/util/flash_ctrl_gen.py && git diff --exit-code
if [[ $? != 0 ]]; then
  echo -n "##vso[task.logissue type=error]"
  echo "Autogenerated flash_ctrl code not up-to-date."
  echo "Regenerate with 'hw/ip/flash_ctrl/util/flash_ctrl_gen.py'."
  exit 1
fi

util/design/secded_gen.py --no_fpv && git diff --exit-code
if [[ $? != 0 ]]; then
  echo -n "##vso[task.logissue type=error]"
  echo "Autogenerated secded primitive code not up-to-date."
  echo "Regenerate with 'util/design/secded_gen.py --no_fpv'."
  exit 1
fi
