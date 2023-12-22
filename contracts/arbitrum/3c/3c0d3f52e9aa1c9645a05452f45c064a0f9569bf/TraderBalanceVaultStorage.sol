// (c) 2023 Primex.finance
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {ERC165Upgradeable} from "./ERC165Upgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";

import {ITraderBalanceVaultStorage} from "./ITraderBalanceVaultStorage.sol";
import {IWhiteBlackList} from "./IWhiteBlackList.sol";

abstract contract TraderBalanceVaultStorage is
    ITraderBalanceVaultStorage,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC165Upgradeable
{
    address public override registry;

    // trader => asset => balance
    mapping(address => mapping(address => TraderBalance)) public override balances;
    IWhiteBlackList internal whiteBlackList;
}

