// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ============================ Base ============================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/Puppet

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Address} from "./Address.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IWETH} from "./IWETH.sol";
import {IOrchestrator, IRoute} from "./IOrchestrator.sol";

/// @title Base
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice An abstract contract that contains common libraries, and constants
abstract contract Base is ReentrancyGuard {

    address internal constant _WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
}
