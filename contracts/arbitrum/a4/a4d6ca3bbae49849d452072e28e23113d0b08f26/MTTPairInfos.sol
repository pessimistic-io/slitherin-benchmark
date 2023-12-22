// SPDX-License-Identifier: MIT
import "./StorageInterfaceV5.sol";
pragma solidity 0.8.10;

contract MTTPairInfos {
    // Addresses
    StorageInterfaceV5 immutable storageT;
    address public manager;

    // Constant parameters
    uint256 constant PRECISION = 1e10; // 10 decimals
    uint256 constant LIQ_THRESHOLD_P = 90; // -90% (of collateral)

    // Adjustable parameters
    uint256 public maxNegativePnlOnOpenP = 40 * PRECISION; // PRECISION (%)

    // Pair parameters
    struct PairParams {
        uint256 onePercentDepthAbove; // DAI
        uint256 onePercentDepthBelow; // DAI
        uint256 rolloverFeePerBlockP; // PRECISION (%)
        uint256 fundingFeePerBlockP; // PRECISION (%)
    }

    mapping(uint256 => PairParams) public pairParams;

    // Pair acc funding fees
    struct PairFundingFees {
        int256 accPerOiLong; // 1e18 (DAI)
        int256 accPerOiShort; // 1e18 (DAI)
        uint256 lastUpdateBlock;
    }

    mapping(uint256 => PairFundingFees) public pairFundingFees;

    // Pair acc rollover fees
    struct PairRolloverFees {
        uint256 accPerCollateral; // 1e18 (DAI)
        uint256 lastUpdateBlock;
    }

    mapping(uint256 => PairRolloverFees) public pairRolloverFees;

    // Trade initial acc fees
    struct TradeInitialAccFees {
        uint256 rollover; // 1e18 (DAI)
        int256 funding; // 1e18 (DAI)
        bool openedAfterUpdate;
    }

    mapping(address => mapping(uint256 => mapping(uint256 => TradeInitialAccFees)))
        public tradeInitialAccFees;

    // Events
    event ManagerUpdated(address value);
    event MaxNegativePnlOnOpenPUpdated(uint256 value);

    event PairParamsUpdated(uint256 pairIndex, PairParams value);
    event OnePercentDepthUpdated(
        uint256 pairIndex,
        uint256 valueAbove,
        uint256 valueBelow
    );
    event RolloverFeePerBlockPUpdated(uint256 pairIndex, uint256 value);
    event FundingFeePerBlockPUpdated(uint256 pairIndex, uint256 value);

    event TradeInitialAccFeesStored(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 rollover,
        int256 funding
    );

    event AccFundingFeesStored(
        uint256 pairIndex,
        int256 valueLong,
        int256 valueShort
    );
    event AccRolloverFeesStored(uint256 pairIndex, uint256 value);

    event FeesCharged(
        uint256 pairIndex,
        bool long,
        uint256 collateral, // 1e18 (DAI)
        uint256 leverage,
        int256 percentProfit, // PRECISION (%)
        uint256 rolloverFees, // 1e18 (DAI)
        int256 fundingFees // 1e18 (DAI)
    );

    constructor(StorageInterfaceV5 _storageT) {
        storageT = _storageT;
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyManager() {
        require(msg.sender == manager, "MANAGER_ONLY");
        _;
    }
    modifier onlyCallbacks() {
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");
        _;
    }

    // Set manager address
    function setManager(address _manager) external onlyGov {
        manager = _manager;

        emit ManagerUpdated(_manager);
    }

    // Set max negative PnL % on trade opening
    function setMaxNegativePnlOnOpenP(uint256 value) external onlyManager {
        maxNegativePnlOnOpenP = value;

        emit MaxNegativePnlOnOpenPUpdated(value);
    }

    // Set parameters for pair
    function setPairParams(uint256 pairIndex, PairParams memory value)
        public
        onlyManager
    {
        storeAccRolloverFees(pairIndex);
        storeAccFundingFees(pairIndex);

        pairParams[pairIndex] = value;

        emit PairParamsUpdated(pairIndex, value);
    }

    function setPairParamsArray(
        uint256[] memory indices,
        PairParams[] memory values
    ) external onlyManager {
        require(indices.length == values.length, "WRONG_LENGTH");

        for (uint256 i = 0; i < indices.length; i++) {
            setPairParams(indices[i], values[i]);
        }
    }

    // Set one percent depth for pair
    function setOnePercentDepth(
        uint256 pairIndex,
        uint256 valueAbove,
        uint256 valueBelow
    ) public onlyManager {
        PairParams storage p = pairParams[pairIndex];

        p.onePercentDepthAbove = valueAbove;
        p.onePercentDepthBelow = valueBelow;

        emit OnePercentDepthUpdated(pairIndex, valueAbove, valueBelow);
    }

    function setOnePercentDepthArray(
        uint256[] memory indices,
        uint256[] memory valuesAbove,
        uint256[] memory valuesBelow
    ) external onlyManager {
        require(
            indices.length == valuesAbove.length &&
                indices.length == valuesBelow.length,
            "WRONG_LENGTH"
        );

        for (uint256 i = 0; i < indices.length; i++) {
            setOnePercentDepth(indices[i], valuesAbove[i], valuesBelow[i]);
        }
    }

    // Set rollover fee for pair
    function setRolloverFeePerBlockP(uint256 pairIndex, uint256 value)
        public
        onlyManager
    {
        require(value <= 25000000, "TOO_HIGH"); // ≈ 100% per day

        storeAccRolloverFees(pairIndex);

        pairParams[pairIndex].rolloverFeePerBlockP = value;

        emit RolloverFeePerBlockPUpdated(pairIndex, value);
    }

    function setRolloverFeePerBlockPArray(
        uint256[] memory indices,
        uint256[] memory values
    ) external onlyManager {
        require(indices.length == values.length, "WRONG_LENGTH");

        for (uint256 i = 0; i < indices.length; i++) {
            setRolloverFeePerBlockP(indices[i], values[i]);
        }
    }

    // Set funding fee for pair
    function setFundingFeePerBlockP(uint256 pairIndex, uint256 value)
        public
        onlyManager
    {
        require(value <= 10000000, "TOO_HIGH"); // ≈ 40% per day

        storeAccFundingFees(pairIndex);

        pairParams[pairIndex].fundingFeePerBlockP = value;

        emit FundingFeePerBlockPUpdated(pairIndex, value);
    }

    function setFundingFeePerBlockPArray(
        uint256[] memory indices,
        uint256[] memory values
    ) external onlyManager {
        require(indices.length == values.length, "WRONG_LENGTH");

        for (uint256 i = 0; i < indices.length; i++) {
            setFundingFeePerBlockP(indices[i], values[i]);
        }
    }

    // Store trade details when opened (acc fee values)
    function storeTradeInitialAccFees(
        address trader,
        uint256 pairIndex,
        uint256 index,
        bool long
    ) external onlyCallbacks {
        storeAccFundingFees(pairIndex);

        TradeInitialAccFees storage t = tradeInitialAccFees[trader][pairIndex][
            index
        ];

        t.rollover = getPendingAccRolloverFees(pairIndex);

        t.funding = long
            ? pairFundingFees[pairIndex].accPerOiLong
            : pairFundingFees[pairIndex].accPerOiShort;

        t.openedAfterUpdate = true;

        emit TradeInitialAccFeesStored(
            trader,
            pairIndex,
            index,
            t.rollover,
            t.funding
        );
    }

    // Acc rollover fees (store right before fee % update)
    function storeAccRolloverFees(uint256 pairIndex) private {
        PairRolloverFees storage r = pairRolloverFees[pairIndex];

        r.accPerCollateral = getPendingAccRolloverFees(pairIndex);
        r.lastUpdateBlock = block.number;

        emit AccRolloverFeesStored(pairIndex, r.accPerCollateral);
    }

    function getPendingAccRolloverFees(uint256 pairIndex)
        public
        view
        returns (uint256)
    {
        // 1e18 (DAI)
        PairRolloverFees storage r = pairRolloverFees[pairIndex];

        return
            r.accPerCollateral +
            ((block.number - r.lastUpdateBlock) *
                pairParams[pairIndex].rolloverFeePerBlockP *
                1e18) /
            PRECISION /
            100;
    }

    // Acc funding fees (store right before trades opened / closed and fee % update)
    function storeAccFundingFees(uint256 pairIndex) private {
        PairFundingFees storage f = pairFundingFees[pairIndex];

        (f.accPerOiLong, f.accPerOiShort) = getPendingAccFundingFees(pairIndex);
        f.lastUpdateBlock = block.number;

        emit AccFundingFeesStored(pairIndex, f.accPerOiLong, f.accPerOiShort);
    }

    function getPendingAccFundingFees(uint256 pairIndex)
        public
        view
        returns (int256 valueLong, int256 valueShort)
    {
        PairFundingFees storage f = pairFundingFees[pairIndex];

        valueLong = f.accPerOiLong;
        valueShort = f.accPerOiShort;

        int256 openInterestDaiLong = int256(
            storageT.openInterestDai(pairIndex, 0)
        );
        int256 openInterestDaiShort = int256(
            storageT.openInterestDai(pairIndex, 1)
        );

        int256 fundingFeesPaidByLongs = ((openInterestDaiLong -
            openInterestDaiShort) *
            int256(block.number - f.lastUpdateBlock) *
            int256(pairParams[pairIndex].fundingFeePerBlockP)) /
            int256(PRECISION) /
            100;

        if (openInterestDaiLong > 0) {
            valueLong += (fundingFeesPaidByLongs * 1e18) / openInterestDaiLong;
        }

        if (openInterestDaiShort > 0) {
            valueShort +=
                (fundingFeesPaidByLongs * 1e18 * (-1)) /
                openInterestDaiShort;
        }
    }

    // Dynamic price impact value on trade opening
    function getTradePriceImpact(
        uint256 openPrice, // PRECISION
        uint256 pairIndex,
        bool long,
        uint256 tradeOpenInterest // 1e18 (DAI)
    )
        external
        view
        returns (
            uint256 priceImpactP, // PRECISION (%)
            uint256 priceAfterImpact // PRECISION
        )
    {
        (priceImpactP, priceAfterImpact) = getTradePriceImpactPure(
            openPrice,
            long,
            storageT.openInterestDai(pairIndex, long ? 0 : 1),
            tradeOpenInterest,
            long
                ? pairParams[pairIndex].onePercentDepthAbove
                : pairParams[pairIndex].onePercentDepthBelow
        );
    }

    function getTradePriceImpactPure(
        uint256 openPrice, // PRECISION
        bool long,
        uint256 startOpenInterest, // 1e18 (DAI)
        uint256 tradeOpenInterest, // 1e18 (DAI)
        uint256 onePercentDepth
    )
        public
        view
        returns (
            uint256 priceImpactP, // PRECISION (%)
            uint256 priceAfterImpact // PRECISION
        )
    {
        if (onePercentDepth == 0) {
            return (0, openPrice);
        }

        priceImpactP =
            ((startOpenInterest + tradeOpenInterest / 2) * PRECISION) /
            1e18 /
            onePercentDepth;

        uint256 priceImpact = (priceImpactP * openPrice) / PRECISION / 100;

        priceAfterImpact = long
            ? openPrice + priceImpact
            : openPrice - priceImpact;
    }

    // Rollover fee value
    function getTradeRolloverFee(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 collateral // 1e18 (DAI)
    ) public view returns (uint256) {
        // 1e18 (DAI)
        TradeInitialAccFees memory t = tradeInitialAccFees[trader][pairIndex][
            index
        ];

        if (!t.openedAfterUpdate) {
            return 0;
        }

        return
            getTradeRolloverFeePure(
                t.rollover,
                getPendingAccRolloverFees(pairIndex),
                collateral
            );
    }

    function getTradeRolloverFeePure(
        uint256 accRolloverFeesPerCollateral,
        uint256 endAccRolloverFeesPerCollateral,
        uint256 collateral // 1e18 (DAI)
    ) public pure returns (uint256) {
        // 1e18 (DAI)
        return
            ((endAccRolloverFeesPerCollateral - accRolloverFeesPerCollateral) *
                collateral) / 1e18;
    }

    // Funding fee value
    function getTradeFundingFee(
        address trader,
        uint256 pairIndex,
        uint256 index,
        bool long,
        uint256 collateral, // 1e18 (DAI)
        uint256 leverage
    )
        public
        view
        returns (
            int256 // 1e18 (DAI) | Positive => Fee, Negative => Reward
        )
    {
        TradeInitialAccFees memory t = tradeInitialAccFees[trader][pairIndex][
            index
        ];

        if (!t.openedAfterUpdate) {
            return 0;
        }

        (int256 pendingLong, int256 pendingShort) = getPendingAccFundingFees(
            pairIndex
        );

        return
            getTradeFundingFeePure(
                t.funding,
                long ? pendingLong : pendingShort,
                collateral,
                leverage
            );
    }

    function getTradeFundingFeePure(
        int256 accFundingFeesPerOi,
        int256 endAccFundingFeesPerOi,
        uint256 collateral, // 1e18 (DAI)
        uint256 leverage
    )
        public
        pure
        returns (
            int256 // 1e18 (DAI) | Positive => Fee, Negative => Reward
        )
    {
        return
            ((endAccFundingFeesPerOi - accFundingFeesPerOi) *
                int256(collateral) *
                int256(leverage)) / 1e18;
    }

    // Liquidation price value after rollover and funding fees
    function getTradeLiquidationPrice(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 openPrice, // PRECISION
        bool long,
        uint256 collateral, // 1e18 (DAI)
        uint256 leverage
    ) external view returns (uint256) {
        // PRECISION
        return
            getTradeLiquidationPricePure(
                openPrice,
                long,
                collateral,
                leverage,
                getTradeRolloverFee(trader, pairIndex, index, collateral),
                getTradeFundingFee(
                    trader,
                    pairIndex,
                    index,
                    long,
                    collateral,
                    leverage
                )
            );
    }

    function getTradeLiquidationPricePure(
        uint256 openPrice, // PRECISION
        bool long,
        uint256 collateral, // 1e18 (DAI)
        uint256 leverage,
        uint256 rolloverFee, // 1e18 (DAI)
        int256 fundingFee // 1e18 (DAI)
    ) public pure returns (uint256) {
        // PRECISION
        int256 liqPriceDistance = (int256(openPrice) *
            (int256((collateral * LIQ_THRESHOLD_P) / 100) -
                int256(rolloverFee) -
                fundingFee)) /
            int256(collateral) /
            int256(leverage);

        int256 liqPrice = long
            ? int256(openPrice) - liqPriceDistance
            : int256(openPrice) + liqPriceDistance;

        return liqPrice > 0 ? uint256(liqPrice) : 0;
    }

    // Dai sent to trader after PnL and fees
    function getTradeValue(
        address trader,
        uint256 pairIndex,
        uint256 index,
        bool long,
        uint256 collateral, // 1e18 (DAI)
        uint256 leverage,
        int256 percentProfit, // PRECISION (%)
        uint256 closingFee // 1e18 (DAI)
    ) external onlyCallbacks returns (uint256 amount) {
        // 1e18 (DAI)
        storeAccFundingFees(pairIndex);

        uint256 r = getTradeRolloverFee(trader, pairIndex, index, collateral);
        int256 f = getTradeFundingFee(
            trader,
            pairIndex,
            index,
            long,
            collateral,
            leverage
        );

        amount = getTradeValuePure(collateral, percentProfit, r, f, closingFee);

        emit FeesCharged(
            pairIndex,
            long,
            collateral,
            leverage,
            percentProfit,
            r,
            f
        );
    }

    function getTradeValuePure(
        uint256 collateral, // 1e18 (DAI)
        int256 percentProfit, // PRECISION (%)
        uint256 rolloverFee, // 1e18 (DAI)
        int256 fundingFee, // 1e18 (DAI)
        uint256 closingFee // 1e18 (DAI)
    ) public pure returns (uint256) {
        // 1e18 (DAI)
        int256 value = int256(collateral) +
            (int256(collateral) * percentProfit) /
            int256(PRECISION) /
            100 -
            int256(rolloverFee) -
            fundingFee;

        if (
            value <= (int256(collateral) * int256(100 - LIQ_THRESHOLD_P)) / 100
        ) {
            return 0;
        }

        value -= int256(closingFee);

        return value > 0 ? uint256(value) : 0;
    }

    // Useful getters
    function getPairInfos(uint256[] memory indices)
        external
        view
        returns (
            PairParams[] memory,
            PairRolloverFees[] memory,
            PairFundingFees[] memory
        )
    {
        PairParams[] memory params = new PairParams[](indices.length);
        PairRolloverFees[] memory rolloverFees = new PairRolloverFees[](
            indices.length
        );
        PairFundingFees[] memory fundingFees = new PairFundingFees[](
            indices.length
        );

        for (uint256 i = 0; i < indices.length; i++) {
            uint256 index = indices[i];

            params[i] = pairParams[index];
            rolloverFees[i] = pairRolloverFees[index];
            fundingFees[i] = pairFundingFees[index];
        }

        return (params, rolloverFees, fundingFees);
    }

    function getOnePercentDepthAbove(uint256 pairIndex)
        external
        view
        returns (uint256)
    {
        return pairParams[pairIndex].onePercentDepthAbove;
    }

    function getOnePercentDepthBelow(uint256 pairIndex)
        external
        view
        returns (uint256)
    {
        return pairParams[pairIndex].onePercentDepthBelow;
    }

    function getRolloverFeePerBlockP(uint256 pairIndex)
        external
        view
        returns (uint256)
    {
        return pairParams[pairIndex].rolloverFeePerBlockP;
    }

    function getFundingFeePerBlockP(uint256 pairIndex)
        external
        view
        returns (uint256)
    {
        return pairParams[pairIndex].fundingFeePerBlockP;
    }

    function getAccRolloverFees(uint256 pairIndex)
        external
        view
        returns (uint256)
    {
        return pairRolloverFees[pairIndex].accPerCollateral;
    }

    function getAccRolloverFeesUpdateBlock(uint256 pairIndex)
        external
        view
        returns (uint256)
    {
        return pairRolloverFees[pairIndex].lastUpdateBlock;
    }

    function getAccFundingFeesLong(uint256 pairIndex)
        external
        view
        returns (int256)
    {
        return pairFundingFees[pairIndex].accPerOiLong;
    }

    function getAccFundingFeesShort(uint256 pairIndex)
        external
        view
        returns (int256)
    {
        return pairFundingFees[pairIndex].accPerOiShort;
    }

    function getAccFundingFeesUpdateBlock(uint256 pairIndex)
        external
        view
        returns (uint256)
    {
        return pairFundingFees[pairIndex].lastUpdateBlock;
    }

    function getTradeInitialAccRolloverFeesPerCollateral(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) external view returns (uint256) {
        return tradeInitialAccFees[trader][pairIndex][index].rollover;
    }

    function getTradeInitialAccFundingFeesPerOi(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) external view returns (int256) {
        return tradeInitialAccFees[trader][pairIndex][index].funding;
    }

    function getTradeOpenedAfterUpdate(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) external view returns (bool) {
        return tradeInitialAccFees[trader][pairIndex][index].openedAfterUpdate;
    }
}

