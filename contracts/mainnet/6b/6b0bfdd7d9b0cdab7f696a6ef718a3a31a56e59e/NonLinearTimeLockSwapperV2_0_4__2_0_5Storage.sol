// SPDX-License-Identifier: MIT

pragma solidity 0.8.5; // solhint-disable-line compiler-version

import { IERC20 } from "./IERC20.sol";

import { Kernel } from "./Kernel.sol";

abstract contract NonLinearTimeLockSwapperV2_0_4__2_0_5Storage is Kernel {
    // swap data for each source token, i.e., teamCFX, ecoCFX, backCFX
    struct SourceTokeData {
        uint128 rate; // convertion rate from source token to target token
        uint128 startTime;
        uint256[] stepEndTimes;
        uint256[] accStepRatio;
    }

    IERC20 public token; // target token, i.e., CFX
    address public tokenWallet; // address who supply target token

    /// @dev `migrationStopped` is deprecated. this exists only to remain storage layout.
    bool public _____DEPRECATED_____migrationStopped;

    // time lock data for each source token
    mapping(address => SourceTokeData) public sourceTokenDatas;

    // source token deposit amounts
    // sourceToken => beneficiary => deposit amounts
    mapping(address => mapping(address => uint256)) public depositAmounts;

    // source token claimed amounts
    // sourceToken => beneficiary => claimed amounts
    mapping(address => mapping(address => uint256)) public claimedAmounts;
}

