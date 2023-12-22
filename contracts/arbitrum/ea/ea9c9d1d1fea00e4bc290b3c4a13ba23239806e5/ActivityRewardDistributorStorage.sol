// (c) 2023 Primex.finance
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {ERC165Upgradeable} from "./ERC165Upgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";

import "./Errors.sol";

import {IActivityRewardDistributorStorage, IERC20, IPrimexDNS, ITraderBalanceVault} from "./IActivityRewardDistributorStorage.sol";
import {IWhiteBlackList} from "./IWhiteBlackList.sol";

abstract contract ActivityRewardDistributorStorage is
    IActivityRewardDistributorStorage,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC165Upgradeable
{
    IERC20 public override pmx;
    IPrimexDNS public override dns;
    address public override registry;
    address public override treasury;
    ITraderBalanceVault public override traderBalanceVault;
    mapping(address => BucketInfo[2]) public buckets;
    IWhiteBlackList internal whiteBlackList;
}

