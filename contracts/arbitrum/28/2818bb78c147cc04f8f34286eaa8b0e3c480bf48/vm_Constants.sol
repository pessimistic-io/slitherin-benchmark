/**
 * Constants for the ycVM.
 * Just the flags of each operation and etc
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Types.sol";

contract Constants {
    // ================
    //    CONSTANTS
    // ================
    bytes1 internal constant VALUE_VAR_FLAG = 0x00;
    bytes1 internal constant REF_VAR_FLAG = 0x01;
    bytes1 internal constant COMMANDS_LIST_FLAG = 0x02;
    bytes1 internal constant COMMANDS_REF_ARR_FLAG = 0x03;
    bytes1 internal constant RAW_REF_VAR_FLAG = 0x04;
    bytes1 internal constant STATICCALL_COMMAND_FLAG = 0x05;
    bytes1 internal constant CALL_COMMAND_FLAG = 0x06;
    bytes1 internal constant DELEGATECALL_COMMAND_FLAG = 0x07;
    bytes1 internal constant INTERNAL_LOAD_FLAG = 0x08;
    bytes1 internal constant MVC_FLAG = 0xff;

    bytes32 internal constant NULLISH_COMMAND =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
}

