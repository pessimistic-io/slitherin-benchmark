// (c) 2023 Primex.finance
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {ERC165Upgradeable} from "./ERC165Upgradeable.sol";
import {IERC165Upgradeable} from "./IERC165Upgradeable.sol";
import {IAccessControl} from "./IAccessControl.sol";
import {IPool} from "./IPool.sol";
import {IAToken} from "./IAToken.sol";

import {PrimexPricingLibrary} from "./PrimexPricingLibrary.sol";
import "./Errors.sol";

import {IWhiteBlackList} from "./IWhiteBlackList.sol";
import {IBucketStorage} from "./IBucketStorage.sol";
import {IPToken} from "./IPToken.sol";
import {IDebtToken} from "./IDebtToken.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {IPrimexDNS} from "./IPrimexDNS.sol";
import {IPrimexDNSStorage} from "./IPrimexDNSStorage.sol";
import {IReserve} from "./IReserve.sol";
import {IInterestRateStrategy} from "./IInterestRateStrategy.sol";
import {ISwapManager} from "./ISwapManager.sol";
import {ILiquidityMiningRewardDistributor} from "./ILiquidityMiningRewardDistributor.sol";

abstract contract BucketStorage is IBucketStorage, ReentrancyGuardUpgradeable, ERC165Upgradeable {
    string public override name;
    address public override registry;
    IPositionManager public override positionManager;
    IReserve public override reserve;
    IPToken public override pToken;
    IDebtToken public override debtToken;
    IERC20Metadata public override borrowedAsset;
    uint256 public override feeBuffer;
    // The current borrow rate, expressed in ray. bar = borrowing annual rate (originally APR)
    uint128 public override bar;
    // The current interest rate, expressed in ray. lar = lending annual rate (originally APY)
    uint128 public override lar;
    // The estimated borrowing annual rate, expressed in ray
    uint128 public override estimatedBar;
    // The estimated lending annual rate, expressed in ray
    uint128 public override estimatedLar;
    uint128 public override liquidityIndex;
    uint128 public override variableBorrowIndex;
    // block where indexes were updated
    uint256 public lastUpdatedBlockTimestamp;
    uint256 public override permanentLossScaled;
    uint256 public reserveRate;
    uint256 public override withdrawalFeeRate;
    IWhiteBlackList public override whiteBlackList;
    mapping(address => Asset) public override allowedAssets;
    IInterestRateStrategy public interestRateStrategy;
    uint256 public aaveDeposit;
    bool public isReinvestToAaveEnabled;
    uint256 public override maxTotalDeposit;
    address[] internal assets;
    // solhint-disable-next-line var-name-mixedcase
    LiquidityMiningParams internal LMparams;
    IPrimexDNS internal dns;
    IPriceOracle internal priceOracle;
}

