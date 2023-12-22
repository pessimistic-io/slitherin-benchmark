// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "./LibSubAccount.sol";
import "./Storage.sol";

contract Getter is Storage {
    using LibSubAccount for bytes32;

    function getAssetInfo(uint8 assetId) external view returns (Asset memory) {
        require(assetId < _storage.assets.length, "LST"); // the asset is not LiSTed
        return _storage.assets[assetId];
    }

    function getAllAssetInfo() external view returns (Asset[] memory) {
        return _storage.assets;
    }

    function getAssetAddress(uint8 assetId) external view returns (address) {
        require(assetId < _storage.assets.length, "LST"); // the asset is not LiSTed
        return _storage.assets[assetId].tokenAddress;
    }

    /**
     * @return numbers [ 0] shortFundingBaseRate8H
     *                 [ 1] shortFundingLimitRate8H
     *                 [ 2] lastFundingTime
     *                 [ 3] fundingInterval
     *                 [ 4] liquidityBaseFeeRate
     *                 [ 5] liquidityDynamicFeeRate
     *                 [ 6] sequence. note: will be 0 after 0xffffffff
     *                 [ 7] strictStableDeviation
     *                 [ 8] mlpPriceLowerBound
     *                 [ 9] mlpPriceUpperBound
     *                 [10] brokerGasRebate
     */
    function getLiquidityPoolStorage() external view returns (uint256[11] memory numbers) {
        numbers[0] = _storage.shortFundingBaseRate8H;
        numbers[1] = _storage.shortFundingLimitRate8H;
        numbers[2] = _storage.lastFundingTime;
        numbers[3] = _storage.fundingInterval;
        numbers[4] = _storage.liquidityBaseFeeRate;
        numbers[5] = _storage.liquidityDynamicFeeRate;
        numbers[6] = _storage.sequence;
        numbers[7] = _storage.strictStableDeviation;
        numbers[8] = _storage.mlpPriceLowerBound;
        numbers[9] = _storage.mlpPriceUpperBound;
        numbers[10] = _storage.brokerGasRebate;
    }

    function getSubAccount(bytes32 subAccountId)
        external
        view
        returns (
            uint96 collateral,
            uint96 size,
            uint32 lastIncreasedTime,
            uint96 entryPrice,
            uint128 entryFunding
        )
    {
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        collateral = subAccount.collateral;
        size = subAccount.size;
        lastIncreasedTime = subAccount.lastIncreasedTime;
        entryPrice = subAccount.entryPrice;
        entryFunding = subAccount.entryFunding;
    }
}

