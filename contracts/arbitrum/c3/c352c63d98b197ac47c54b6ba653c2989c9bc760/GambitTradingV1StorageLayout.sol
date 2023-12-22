//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";

import "./Delegatable.sol";

import "./IGambitReferralsV1.sol";
import "./IGambitPairInfosV1.sol";
import "./IGambitTradingStorageV1.sol";
import "./IGambitPairsStorageV1.sol";

contract GambitTradingV1StorageLayout is Delegatable, Initializable {
    bytes32[62] private _gap0; // storage slot gap (2 slots for Delegatable and Initializeable)

    // Contracts (constant)
    IGambitTradingStorageV1 public storageT;
    NftRewardsInterfaceV6 public nftRewards;
    IGambitPairInfosV1 public pairInfos;
    IGambitReferralsV1 public referrals;

    bytes32[60] private _gap2; // storage slot gap (4 slots for above variables)

    // Params (constant)
    uint constant PRECISION = 1e10;
    uint constant MAX_SL_P = 75; // -75% PNL

    // Params (adjustable)
    uint public maxPosUsdc; // 1e6 (USDC) or 1e18 (DAI) (eg. 75000 * 1e6)
    uint public limitOrdersTimelock; // batch (zkSync) or block (other) (eg. 30)
    uint public marketOrdersTimeout; // batch (zkSync) or block (other) (eg. 30)

    bytes32[61] private _gap3; // storage slot gap (3 slots for above variables)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    bytes32[63] private _gap4; // storage slot gap (1 slot for above variable)
}

