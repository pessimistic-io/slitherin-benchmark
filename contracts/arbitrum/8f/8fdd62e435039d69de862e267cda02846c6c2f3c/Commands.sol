// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

/// @title Commands
/// @notice Command Flags used to decode commands
library Commands {
    // Masks to extract certain bits of commands
    bytes1 internal constant FLAG_ALLOW_REVERT = 0x80;
    bytes1 internal constant COMMAND_TYPE_MASK = 0x3f;

    // Command Types. Maximum supported command at this moment is 0x3f.
    uint256 constant V2_DATED_IRS_INSTRUMENT_SWAP = 0x00;
    uint256 constant V2_DATED_IRS_INSTRUMENT_SETTLE = 0x01;
    uint256 constant V2_VAMM_EXCHANGE_LP = 0x02;
    uint256 constant V2_CORE_CREATE_ACCOUNT = 0x03;
    uint256 constant V2_CORE_DEPOSIT = 0x04;
    uint256 constant V2_CORE_WITHDRAW = 0x05;
    uint256 constant WRAP_ETH = 0x06;
    uint256 constant TRANSFER_FROM = 0x07;
}

