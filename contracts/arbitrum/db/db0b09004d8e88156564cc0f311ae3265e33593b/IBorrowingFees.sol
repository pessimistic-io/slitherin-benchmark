// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IBorrowingFees {

    struct PairGroup {
        uint16 groupIndex;
        uint48 block;
        uint64 initialAccFeeLong;
        uint64 initialAccFeeShort;
        uint64 prevGroupAccFeeLong;
        uint64 prevGroupAccFeeShort;
        uint64 pairAccFeeLong;
        uint64 pairAccFeeShort;
        uint64 _placeholder; // might be useful later
    }
    struct Pair {
        PairGroup[] groups;
        uint32 feePerBlock;
        uint64 accFeeLong;
        uint64 accFeeShort;
        uint48 accLastUpdatedBlock;
        uint48 _placeholder; // might be useful later
        uint256 lastAccBlockWeightedMarketCap; // 1e40
    }
    struct Group {
        uint112 oiLong;
        uint112 oiShort;
        uint32 feePerBlock;
        uint64 accFeeLong;
        uint64 accFeeShort;
        uint48 accLastUpdatedBlock;
        uint80 maxOi;
        uint256 lastAccBlockWeightedMarketCap;
    }
    struct InitialAccFees {
        uint64 accPairFee;
        uint64 accGroupFee;
        uint48 block;
        uint80 _placeholder; // might be useful later
    }
    struct PairParams {
        uint16 groupIndex;
        uint32 feePerBlock;
    }
    struct GroupParams {
        uint32 feePerBlock;
        uint80 maxOi;
    }
    struct BorrowingFeeInput {
        address trader;
        uint256 pairIndex;
        uint256 index;
        bool long;
        uint256 collateral;
        uint256 leverage;
    }
    struct LiqPriceInput {
        address trader;
        uint256 pairIndex;
        uint256 index;
        uint256 openPrice;
        bool long;
        uint256 collateral;
        uint256 leverage;
    }

    event PairParamsUpdated(uint indexed pairIndex, uint16 indexed groupIndex, uint32 feePerBlock);
    event PairGroupUpdated(uint indexed pairIndex, uint16 indexed prevGroupIndex, uint16 indexed newGroupIndex);
    event GroupUpdated(uint16 indexed groupIndex, uint32 feePerBlock, uint80 maxOi);
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
        uint256 positionSizeStable
    );
    event PairAccFeesUpdated(
        uint256 indexed pairIndex,
        uint256 currentBlock,
        uint64 accFeeLong,
        uint64 accFeeShort,
        uint256 accBlockWeightedMarketCap
    );
    event GroupAccFeesUpdated(
        uint16 indexed groupIndex,
        uint256 currentBlock,
        uint64 accFeeLong,
        uint64 accFeeShort,
        uint256 accBlockWeightedMarketCap
    );
    event GroupOiUpdated(
        uint16 indexed groupIndex,
        bool indexed long,
        bool indexed increase,
        uint112 amount,
        uint112 oiLong,
        uint112 oiShort
    );

    function getTradeLiquidationPrice(LiqPriceInput calldata) external view returns (uint256);

    function getTradeBorrowingFee(BorrowingFeeInput memory) external view returns (uint256);

    function handleTradeAction(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 positionSizeStable, // (collateral * leverage)
        bool open,
        bool long
    ) external;

    function withinMaxGroupOi(uint256 pairIndex, bool long, uint256 positionSizeStable) external view returns (bool);
}

