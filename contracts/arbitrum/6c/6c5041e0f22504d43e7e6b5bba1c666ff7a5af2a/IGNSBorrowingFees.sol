// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./PriceImpactUtils.sol";

/**
 * @custom:version 6.4.2
 */
interface IGNSBorrowingFees {
    // Structs
    struct PairGroup {
        uint16 groupIndex;
        uint48 block;
        uint64 initialAccFeeLong; // 1e10 (%)
        uint64 initialAccFeeShort; // 1e10 (%)
        uint64 prevGroupAccFeeLong; // 1e10 (%)
        uint64 prevGroupAccFeeShort; // 1e10 (%)
        uint64 pairAccFeeLong; // 1e10 (%)
        uint64 pairAccFeeShort; // 1e10 (%)
        uint64 _placeholder; // might be useful later
    }
    struct Pair {
        PairGroup[] groups;
        uint32 feePerBlock; // 1e10 (%)
        uint64 accFeeLong; // 1e10 (%)
        uint64 accFeeShort; // 1e10 (%)
        uint48 accLastUpdatedBlock;
        uint48 feeExponent;
        uint256 lastAccBlockWeightedMarketCap; // 1e40
    }
    struct PairOi {
        uint72 long; // 1e10 (DAI)
        uint72 short; // 1e10 (DAI)
        uint72 max; // 1e10 (DAI)
        uint40 _placeholder; // might be useful later
    }
    struct Group {
        uint112 oiLong; // 1e10
        uint112 oiShort; // 1e10
        uint32 feePerBlock; // 1e10 (%)
        uint64 accFeeLong; // 1e10 (%)
        uint64 accFeeShort; // 1e10 (%)
        uint48 accLastUpdatedBlock;
        uint80 maxOi; // 1e10
        uint256 lastAccBlockWeightedMarketCap; // 1e40
    }
    struct InitialAccFees {
        uint64 accPairFee; // 1e10 (%)
        uint64 accGroupFee; // 1e10 (%)
        uint48 block;
        uint80 _placeholder; // might be useful later
    }
    struct PairParams {
        uint16 groupIndex;
        uint32 feePerBlock; // 1e10 (%)
        uint48 feeExponent;
        uint72 maxOi;
    }
    struct GroupParams {
        uint32 feePerBlock; // 1e10 (%)
        uint72 maxOi; // 1e10
        uint48 feeExponent;
    }
    struct BorrowingFeeInput {
        address trader;
        uint256 pairIndex;
        uint256 index;
        bool long;
        uint256 collateral; // 1e18 (DAI)
        uint256 leverage;
    }
    struct LiqPriceInput {
        address trader;
        uint256 pairIndex;
        uint256 index;
        uint256 openPrice; // 1e10
        bool long;
        uint256 collateral; // 1e18 (DAI)
        uint256 leverage;
    }
    struct PendingAccFeesInput {
        uint64 accFeeLong; // 1e10 (%)
        uint64 accFeeShort; // 1e10 (%)
        uint256 oiLong; // 1e18
        uint256 oiShort; // 1e18
        uint32 feePerBlock; // 1e10
        uint256 currentBlock;
        uint256 accLastUpdatedBlock;
        uint72 maxOi; // 1e10
        uint48 feeExponent;
    }

    // Events
    event PairParamsUpdated(
        uint256 indexed pairIndex,
        uint16 indexed groupIndex,
        uint32 feePerBlock,
        uint48 feeExponent,
        uint72 maxOi
    );
    event PairGroupUpdated(uint256 indexed pairIndex, uint16 indexed prevGroupIndex, uint16 indexed newGroupIndex);
    event GroupUpdated(uint16 indexed groupIndex, uint32 feePerBlock, uint72 maxOi, uint48 feeExponent);
    event TradeInitialAccFeesStored(
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint64 initialPairAccFee,
        uint64 initialGroupAccFee
    );
    event TradeActionHandled(
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        bool open,
        bool long,
        uint256 positionSizeDai // 1e18
    );
    event PairAccFeesUpdated(uint256 indexed pairIndex, uint256 currentBlock, uint64 accFeeLong, uint64 accFeeShort);
    event GroupAccFeesUpdated(uint16 indexed groupIndex, uint256 currentBlock, uint64 accFeeLong, uint64 accFeeShort);
    event GroupOiUpdated(
        uint16 indexed groupIndex,
        bool indexed long,
        bool indexed increase,
        uint112 amount,
        uint112 oiLong,
        uint112 oiShort
    );

    // v6.4.2 - PriceImpactUtils events, have to be duplicated (solved after 0.8.20 but can't update bc of PUSH0 opcode)
    event OiWindowsSettingsInitialized(uint48 indexed windowsDuration);

    event PriceImpactWindowsCountUpdated(uint48 indexed windowsCount);
    event PriceImpactWindowsDurationUpdated(uint48 indexed windowsDuration);

    event PriceImpactOpenInterestAdded(PriceImpactUtils.OiWindowUpdate oiWindowUpdate);
    event PriceImpactOpenInterestRemoved(PriceImpactUtils.OiWindowUpdate oiWindowUpdate, bool notOutdated);

    event PriceImpactOiTransferredPairs(
        uint256 pairsCount,
        uint256 prevCurrentWindowId,
        uint256 prevEarliestWindowId,
        uint256 newCurrentWindowId
    );
    event PriceImpactOiTransferredPair(uint256 indexed pairIndex, PriceImpactUtils.PairOi totalPairOi);

    // Functions
    function getTradeLiquidationPrice(LiqPriceInput calldata) external view returns (uint256); // PRECISION

    function getTradeBorrowingFee(BorrowingFeeInput memory) external view returns (uint256); // 1e18 (DAI)

    function handleTradeAction(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 positionSizeDai, // 1e18 (collateral * leverage)
        bool open,
        bool long
    ) external;

    function withinMaxGroupOi(uint256 pairIndex, bool long, uint256 positionSizeDai) external view returns (bool);

    function getPairMaxOi(uint256 pairIndex) external view returns (uint256);

    // v6.4.2 - Functions
    function addPriceImpactOpenInterest(uint256 _openInterest, uint256 _pairIndex, bool _long) external;

    function removePriceImpactOpenInterest(
        uint256 _openInterest,
        uint256 _pairIndex,
        bool _long,
        uint48 _addTs
    ) external;

    function getTradePriceImpact(
        uint256 _openPrice, // PRECISION
        uint256 _pairIndex,
        bool _long,
        uint256 _tradeOpenInterest // 1e18 (DAI)
    )
        external
        view
        returns (
            uint256 priceImpactP, // PRECISION (%)
            uint256 priceAfterImpact // PRECISION
        );
}

