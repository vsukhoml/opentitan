# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
load(
    "//rules/opentitan:defs.bzl",
    "CLEAR_TEST_CMD",
    "opentitan_test",
    "silicon_params",
    "verilator_params",
)
load(":gpio.bzl", "strap_combinations_test")

package(default_visibility = ["//visibility:public"])

strap_combinations_test(
    name = "e2e_weak_straps",
    rom = "//sw/device/silicon_creator/rom:mask_rom_sim_verilator_scr_vmem",
    tags = [
        "verilator",
    ],
)

opentitan_test(
    name = "sw_strap_value",
    srcs = ["sw_straps_test.c"],
    exec_env = {
        "//hw/top_earlgrey:sim_verilator": None,
        "//hw/top_earlgrey:silicon_owner_sival_rom_ext": None,
    },
    silicon = silicon_params(
        test_cmd = """
            --bootstrap="{firmware}"
        """,
        test_harness = "//sw/host/tests/rom/sw_strap_value",
    ),
    verilator = verilator_params(
        timeout = "long",
        test_cmd = CLEAR_TEST_CMD,
        test_harness = "//sw/host/tests/rom/sw_strap_value",
    ),
    deps = [
        "//sw/device/lib/base:status",
        "//sw/device/lib/dif:gpio",
        "//sw/device/lib/dif:pinmux",
        "//sw/device/lib/testing:pinmux_testutils",
        "//sw/device/lib/testing/json:command",
        "//sw/device/lib/testing/test_framework:ottf_main",
        "//sw/device/lib/testing/test_framework:ujson_ottf",
        "//sw/device/lib/ujson",
    ],
)
