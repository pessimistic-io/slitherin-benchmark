// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IStorageInterfaceV5.sol";

abstract contract GNSPairInfosV6_1 {
    // Addresses
    StorageInterfaceV5 public storageT;
    address public manager;

    // Constant parameters
    uint constant PRECISION = 1e10; // 10 decimals
    uint constant LIQ_THRESHOLD_P = 90; // -90% (of collateral)

    // Adjustable parameters
    uint public maxNegativePnlOnOpenP; // PRECISION (%)

    // Pair parameters
    struct PairParams {
        uint onePercentDepthAbove; // DAI
        uint onePercentDepthBelow; // DAI
        uint rolloverFeePerBlockP; // PRECISION (%)
        uint fundingFeePerBlockP; // PRECISION (%)
    }

    mapping(uint => PairParams) public pairParams;

    // Pair acc funding fees
    struct PairFundingFees {
        int accPerOiLong; // 1e18 (DAI)
        int accPerOiShort; // 1e18 (DAI)
        uint lastUpdateBlock;
    }

    mapping(uint => PairFundingFees) public pairFundingFees;

    // Pair acc rollover fees
    struct PairRolloverFees {
        uint accPerCollateral; // 1e18 (DAI)
        uint lastUpdateBlock;
    }

    mapping(uint => PairRolloverFees) public pairRolloverFees;

    // Trade initial acc fees
    struct TradeInitialAccFees {
        uint rollover; // 1e18 (DAI)
        int funding; // 1e18 (DAI)
        bool openedAfterUpdate;
    }

    mapping(address => mapping(uint => mapping(uint => TradeInitialAccFees))) public tradeInitialAccFees;

    // Events
    event ManagerUpdated(address value);
    event MaxNegativePnlOnOpenPUpdated(uint value);

    event PairParamsUpdated(uint pairIndex, PairParams value);
    event OnePercentDepthUpdated(uint pairIndex, uint valueAbove, uint valueBelow);
    event RolloverFeePerBlockPUpdated(uint pairIndex, uint value);
    event FundingFeePerBlockPUpdated(uint pairIndex, uint value);

    event TradeInitialAccFeesStored(address trader, uint pairIndex, uint index, uint rollover, int funding);

    event AccFundingFeesStored(uint pairIndex, int valueLong, int valueShort);
    event AccRolloverFeesStored(uint pairIndex, uint value);

    event FeesCharged(
        uint pairIndex,
        bool long,
        uint collateral, // 1e18 (DAI)
        uint leverage,
        int percentProfit, // PRECISION (%)
        uint rolloverFees, // 1e18 (DAI)
        int fundingFees // 1e18 (DAI)
    );

    function initialize(StorageInterfaceV5 _storageT, address _manager, uint _maxNegativePnlOnOpenP) external virtual;

    // Set manager address
    function setManager(address _manager) external virtual;

    // Set max negative PnL % on trade opening
    function setMaxNegativePnlOnOpenP(uint value) external virtual;

    // Set parameters for pair
    function setPairParams(uint pairIndex, PairParams memory value) public virtual;

    function setPairParamsArray(uint[] memory indices, PairParams[] memory values) external virtual;

    // Set one percent depth for pair
    function setOnePercentDepth(uint pairIndex, uint valueAbove, uint valueBelow) public virtual;

    function setOnePercentDepthArray(
        uint[] memory indices,
        uint[] memory valuesAbove,
        uint[] memory valuesBelow
    ) external virtual;

    // Set rollover fee for pair
    function setRolloverFeePerBlockP(uint pairIndex, uint value) public virtual;

    function setRolloverFeePerBlockPArray(uint[] memory indices, uint[] memory values) external virtual;

    // Set funding fee for pair
    function setFundingFeePerBlockP(uint pairIndex, uint value) public virtual;

    function setFundingFeePerBlockPArray(uint[] memory indices, uint[] memory values) external virtual;

    // Store trade details when opened (acc fee values)
    function storeTradeInitialAccFees(address trader, uint pairIndex, uint index, bool long) external virtual;

    // Acc rollover fees (store right before fee % update)
    function getPendingAccRolloverFees(uint pairIndex) public view virtual returns (uint);

    // Acc funding fees (store right before trades opened / closed and fee % update)
    function getPendingAccFundingFees(uint pairIndex) public view virtual returns (int valueLong, int valueShort);

    // Dynamic price impact value on trade opening
    function getTradePriceImpact(
        uint openPrice, // PRECISION
        uint pairIndex,
        bool long,
        uint tradeOpenInterest // 1e18 (DAI)
    )
        external
        view
        virtual
        returns (
            uint priceImpactP, // PRECISION (%)
            uint priceAfterImpact // PRECISION
        );

    function getTradePriceImpactPure(
        uint openPrice, // PRECISION
        bool long,
        uint startOpenInterest, // 1e18 (DAI)
        uint tradeOpenInterest, // 1e18 (DAI)
        uint onePercentDepth
    )
        public
        pure
        virtual
        returns (
            uint priceImpactP, // PRECISION (%)
            uint priceAfterImpact // PRECISION
        );

    // Rollover fee value
    function getTradeRolloverFee(
        address trader,
        uint pairIndex,
        uint index,
        uint collateral // 1e18 (DAI)
    ) public view virtual returns (uint); // 1e18 (DAI)

    function getTradeRolloverFeePure(
        uint accRolloverFeesPerCollateral,
        uint endAccRolloverFeesPerCollateral,
        uint collateral // 1e18 (DAI)
    ) public pure virtual returns (uint); // 1e18 (DAI)

    // Funding fee value
    function getTradeFundingFee(
        address trader,
        uint pairIndex,
        uint index,
        bool long,
        uint collateral, // 1e18 (DAI)
        uint leverage
    )
        public
        view
        virtual
        returns (
            int // 1e18 (DAI) | Positive => Fee, Negative => Reward
        );

    function getTradeFundingFeePure(
        int accFundingFeesPerOi,
        int endAccFundingFeesPerOi,
        uint collateral, // 1e18 (DAI)
        uint leverage
    )
        public
        pure
        virtual
        returns (
            int // 1e18 (DAI) | Positive => Fee, Negative => Reward
        );

    // Liquidation price value after rollover and funding fees
    function getTradeLiquidationPrice(
        address trader,
        uint pairIndex,
        uint index,
        uint openPrice, // PRECISION
        bool long,
        uint collateral, // 1e18 (DAI)
        uint leverage
    ) external view virtual returns (uint); // PRECISION

    function getTradeLiquidationPricePure(
        uint openPrice, // PRECISION
        bool long,
        uint collateral, // 1e18 (DAI)
        uint leverage,
        uint rolloverFee, // 1e18 (DAI)
        int fundingFee // 1e18 (DAI)
    ) public pure virtual returns (uint); // PRECISION

    // Dai sent to trader after PnL and fees
    function getTradeValue(
        address trader,
        uint pairIndex,
        uint index,
        bool long,
        uint collateral, // 1e18 (DAI)
        uint leverage,
        int percentProfit, // PRECISION (%)
        uint closingFee // 1e18 (DAI)
    ) external virtual returns (uint amount); // 1e18 (DAI)

    function getTradeValuePure(
        uint collateral, // 1e18 (DAI)
        int percentProfit, // PRECISION (%)
        uint rolloverFee, // 1e18 (DAI)
        int fundingFee, // 1e18 (DAI)
        uint closingFee // 1e18 (DAI)
    ) public pure virtual returns (uint); // 1e18 (DAI)

    // Useful getters
    function getPairInfos(
        uint[] memory indices
    ) external view virtual returns (PairParams[] memory, PairRolloverFees[] memory, PairFundingFees[] memory);

    function getOnePercentDepthAbove(uint pairIndex) external view virtual returns (uint);

    function getOnePercentDepthBelow(uint pairIndex) external view virtual returns (uint);

    function getRolloverFeePerBlockP(uint pairIndex) external view virtual returns (uint);

    function getFundingFeePerBlockP(uint pairIndex) external view virtual returns (uint);

    function getAccRolloverFees(uint pairIndex) external view virtual returns (uint);

    function getAccRolloverFeesUpdateBlock(uint pairIndex) external view virtual returns (uint);

    function getAccFundingFeesLong(uint pairIndex) external view virtual returns (int);

    function getAccFundingFeesShort(uint pairIndex) external view virtual returns (int);

    function getAccFundingFeesUpdateBlock(uint pairIndex) external view virtual returns (uint);

    function getTradeInitialAccRolloverFeesPerCollateral(
        address trader,
        uint pairIndex,
        uint index
    ) external view virtual returns (uint);

    function getTradeInitialAccFundingFeesPerOi(
        address trader,
        uint pairIndex,
        uint index
    ) external view virtual returns (int);

    function getTradeOpenedAfterUpdate(address trader, uint pairIndex, uint index) external view virtual returns (bool);
}

