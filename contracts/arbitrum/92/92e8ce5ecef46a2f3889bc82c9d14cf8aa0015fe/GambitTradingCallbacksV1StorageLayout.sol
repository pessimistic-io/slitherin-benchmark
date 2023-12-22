// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";

import "./IGambitTradingStorageV1.sol";
import "./IGambitPairInfosV1.sol";
import "./IGambitReferralsV1.sol";
import "./IGambitStakingV1.sol";

import "./IStableCoinDecimals.sol";

import "./GambitErrorsV1.sol";

contract GambitTradingCallbacksV1StorageLayout is Initializable {
    bytes32[63] private _gap0; // storage slot gap (1 slot for Initializeable)

    // Contracts (constant)
    IGambitTradingStorageV1 public storageT;
    NftRewardsInterfaceV6 public nftRewards;
    IGambitPairInfosV1 public pairInfos;
    IGambitReferralsV1 public referrals;
    IGambitStakingV1 public staking;

    bytes32[59] private _gap1; // storage slot gap (5 slots for above variables)

    // Params (constant)
    uint constant PRECISION = 1e10; // 10 decimals

    uint constant MAX_SL_P = 75; // -75% PNL
    uint constant MAX_GAIN_P = 900; // 900% PnL (10x)

    // Params (adjustable)
    uint public usdcVaultFeeP; // % of closing fee going to USDC vault (eg. 40)
    uint public sssFeeP; // % of closing fee going to CNG staking (eg. 40)

    bytes32[62] private _gap2; // storage slot gap (1 slot for above variable)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    bytes32[63] private _gap3; // storage slot gap (1 slot for above variable)
}

