//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IStableCoinDecimals.sol";
import "./Multicall.sol";

import "./GambitErrorsV1.sol";

import "./GambitTradingV1StorageLayout.sol";

/**
 * @dev GambitTradingV1Base implements events and modifiers and common functions
 */
abstract contract GambitTradingV1Base is
    GambitTradingV1StorageLayout,
    IStableCoinDecimals,
    Multicall
{
    // Events
    event Done(bool done);
    event Paused(bool paused);

    event NumberUpdated(string name, uint value);

    event MarketOrderInitiated(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        bool open
    );

    event OpenLimitPlaced(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        NftRewardsInterfaceV6.OpenLimitOrderType orderType
    );
    event OpenLimitUpdated(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newPrice,
        uint newTp,
        uint newSl
    );
    event OpenLimitCanceled(
        address indexed trader,
        uint indexed pairIndex,
        uint index
    );

    event TpUpdated(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newTp
    );
    event SlUpdated(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newSl
    );
    event SlUpdateInitiated(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint openPrice,
        bool buy,
        uint newSl
    );

    event CollateralAdded(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint amount,
        uint newLeverage
    );

    event CollateralRemoveInitiated(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint openPrice,
        bool buy,
        uint amount
    );

    event NftOrderInitiated(
        uint orderId,
        address indexed nftHolder,
        address indexed trader,
        uint indexed pairIndex
    );
    event NftOrderSameBlock(
        address indexed nftHolder,
        address indexed trader,
        uint indexed pairIndex
    );

    event ChainlinkCallbackTimeout(
        uint indexed orderId,
        IGambitTradingStorageV1.PendingMarketOrder order
    );
    event CouldNotCloseTrade(
        address indexed trader,
        uint indexed pairIndex,
        uint index
    );

    // Modifiers
    modifier onlyGov() {
        if (msg.sender != storageT.gov()) revert GambitErrorsV1.NotGov();
        _;
    }
    modifier notContract() {
        require(tx.origin == msg.sender);
        _;
    }
    modifier notDone() {
        if (isDone) revert GambitErrorsV1.Done();
        _;
    }

    // Avoid stack too deep error in executeNftOrder
    function getTradeLiquidationPrice(
        IGambitTradingStorageV1.Trade memory t
    ) internal view returns (uint) {
        return
            pairInfos.getTradeLiquidationPrice(
                t.trader,
                t.pairIndex,
                t.index,
                t.openPrice,
                t.buy,
                // USDC: 1e18 * 1e10 / 1e10 / 1e12 = 1e6
                // DAI:  1e18 * 1e10 / 1e10 / 1e0 = 1e18
                (t.initialPosToken *
                    storageT
                        .openTradesInfo(t.trader, t.pairIndex, t.index)
                        .tokenPriceUsdc) /
                    PRECISION /
                    (10 ** (18 - usdcDecimals())),
                t.leverage
            );
    }

    function usdcDecimals() public pure virtual returns (uint8);
}

