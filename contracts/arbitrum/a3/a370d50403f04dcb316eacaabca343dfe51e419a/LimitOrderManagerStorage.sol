// (c) 2023 Primex.finance
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IAccessControl} from "./IAccessControl.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {ERC165Upgradeable} from "./ERC165Upgradeable.sol";
import {IERC165Upgradeable} from "./IERC165Upgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {WadRayMath} from "./WadRayMath.sol";

import {PrimexPricingLibrary} from "./PrimexPricingLibrary.sol";
import {TokenTransfersLibrary} from "./TokenTransfersLibrary.sol";
import {LimitOrderLibrary} from "./LimitOrderLibrary.sol";
import "./Errors.sol";

import {IPositionManager} from "./IPositionManager.sol";
import {ILimitOrderManagerStorage} from "./ILimitOrderManagerStorage.sol";
import {ITraderBalanceVault} from "./ITraderBalanceVault.sol";
import {IBucket} from "./IBucket.sol";
import {IPrimexDNS} from "./IPrimexDNS.sol";
import {IConditionalOpeningManager} from "./IConditionalOpeningManager.sol";
import {ISwapManager} from "./ISwapManager.sol";
import {IWhiteBlackList} from "./IWhiteBlackList.sol";

abstract contract LimitOrderManagerStorage is
    ILimitOrderManagerStorage,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC165Upgradeable
{
    LimitOrderLibrary.LimitOrder[] internal orders;
    uint256 public override ordersId;
    mapping(uint256 => uint256) public override orderIndexes;
    // mapping from orderId to the index in the traderOrderIds[trader] array
    mapping(uint256 => uint256) public override traderOrderIndexes;
    // mapping from trader address to the order ids array
    mapping(address => uint256[]) public override traderOrderIds;
    // mapping from orderId to the index in the bucketOrderIds[bucket] array
    mapping(uint256 => uint256) public override bucketOrderIndexes;
    // mapping from bucket address to the order ids array
    mapping(address => uint256[]) public override bucketOrderIds;
    // mapping from order to open conditions
    mapping(uint256 => LimitOrderLibrary.Condition[]) public openConditions;
    // mapping from order to close conditions
    mapping(uint256 => LimitOrderLibrary.Condition[]) public closeConditions;

    IAccessControl public override registry;
    ITraderBalanceVault public override traderBalanceVault;
    IPrimexDNS public override primexDNS;
    IPositionManager public override pm;
    ISwapManager public override swapManager;
    IWhiteBlackList internal whiteBlackList;
}

