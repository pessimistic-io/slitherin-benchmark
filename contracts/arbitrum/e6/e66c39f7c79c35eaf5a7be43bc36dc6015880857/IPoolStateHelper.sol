// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ILeveragedPool} from "./ILeveragedPool.sol";

struct ExpectedPoolState {
	//in settlementToken decimals
	uint256 cumulativePendingMintSettlement;
	uint256 remainingPendingShortBurnTokens;
	uint256 remainingPendingLongBurnTokens;
	uint256 longSupply;
	uint256 longBalance;
	uint256 shortSupply;
	uint256 shortBalance;
	int256 oraclePrice;
}

interface ILeveragedPool2 is ILeveragedPool {
    function fee() external view returns (bytes16);

    function keeper() external view returns (address);

    function leverageAmount() external view override returns (bytes16);
}

interface IPoolStateHelper {
    error INVALID_PERIOD();

    struct SideInfo {
        uint256 supply; // poolToken.totalSupply()
        uint256 settlementBalance; // balance of settlementTokens associated with supply
        uint256 pendingBurnPoolTokens;
    }

    struct PoolInfo {
        SideInfo long;
        SideInfo short;
    }

    struct SMAInfo {
        int256[] prices;
        uint256 numPeriods;
    }

    function getExpectedState(ILeveragedPool2 pool, uint256 periods)
        external
        view
        returns (ExpectedPoolState memory finalExpectedPoolState);
}


