// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import { BlockContext } from "./BlockContext.sol";
import { IPriceFeed } from "./IPriceFeed.sol";
import { IERC20 } from "./IERC20.sol";
import { OwnableUpgradeableSafe } from "./OwnableUpgradeableSafe.sol";
import { IAmm } from "./IAmm.sol";
import { IntMath } from "./IntMath.sol";
import { UIntMath } from "./UIntMath.sol";
import { Math } from "./Math.sol";
import { AmmMath } from "./AmmMath.sol";

contract Amm is IAmm, OwnableUpgradeableSafe, BlockContext {
    using UIntMath for uint256;
    using IntMath for int256;

    //
    // enum and struct
    //

    // internal usage
    enum QuoteAssetDir {
        QUOTE_IN,
        QUOTE_OUT
    }

    struct ReserveSnapshot {
        uint256 quoteAssetReserve;
        uint256 baseAssetReserve;
        uint256 cumulativeTWPBefore; // cumulative time weighted price of market before the current block, used for TWAP calculation
        uint256 timestamp;
        uint256 blockNumber;
    }

    // To record current base/quote asset to calculate TWAP

    struct TwapInputAsset {
        Dir dir;
        uint256 assetAmount;
        QuoteAssetDir inOrOut;
    }

    struct TwapPriceCalcParams {
        uint16 snapshotIndex;
        TwapInputAsset asset;
    }

    //
    // CONSTANT
    //
    // because position decimal rounding error,
    // if the position size is less than IGNORABLE_DIGIT_FOR_SHUTDOWN, it's equal size is 0
    uint256 private constant IGNORABLE_DIGIT_FOR_SHUTDOWN = 1e9;

    uint256 public constant MAX_ORACLE_SPREAD_RATIO = 0.05 ether; // 5%

    uint8 public constant MIN_NUM_REPEG_FLAG = 3;

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    // only admin
    uint256 public override initMarginRatio;

    // only admin
    uint256 public override maintenanceMarginRatio;

    // only admin
    uint256 public override liquidationFeeRatio;

    // only admin
    uint256 public override partialLiquidationRatio;

    uint256 public longPositionSize;
    uint256 public shortPositionSize;

    int256 private cumulativeNotional;

    uint256 private settlementPrice;
    uint256 public tradeLimitRatio;
    uint256 public quoteAssetReserve;
    uint256 public baseAssetReserve;
    uint256 public fluctuationLimitRatio;

    // owner can update
    uint256 public tollRatio;
    uint256 public spreadRatio;

    uint256 public spotPriceTwapInterval;
    uint256 public fundingPeriod;
    uint256 public fundingBufferPeriod;
    uint256 public nextFundingTime;
    bytes32 public priceFeedKey;
    // this storage variable is used for TWAP calcualtion
    // let's use 15 mins and 3 hr twap as example
    // if the price is being updated 1 secs, then needs 900 and 10800 historical data for 15mins and 3hr twap.
    ReserveSnapshot[65536] public reserveSnapshots; // 2**16=65536
    uint16 public latestReserveSnapshotIndex;

    address private counterParty;
    address public globalShutdown;
    IERC20 public override quoteAsset;
    IPriceFeed public priceFeed;
    bool public override open;
    bool public override adjustable;
    bool public override canLowerK;
    uint8 public repegFlag;
    uint256 public repegPriceGapRatio;

    uint256 public fundingCostCoverRate; // system covers pct of normal funding payment when cost, 1 means normal funding rate
    uint256 public fundingRevenueTakeRate; // system takes ptc of normal funding payment when revenue, 1 means normal funding rate

    uint256 public override ptcKIncreaseMax;
    uint256 public override ptcKDecreaseMax;

    uint256[50] private __gap;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//

    //
    // EVENTS
    //
    event SwapInput(Dir dirOfQuote, uint256 quoteAssetAmount, uint256 baseAssetAmount);
    event SwapOutput(Dir dirOfQuote, uint256 quoteAssetAmount, uint256 baseAssetAmount);
    event FundingRateUpdated(int256 rateLong, int256 rateShort, uint256 underlyingPrice, int256 fundingPayment);
    event ReserveSnapshotted(uint256 quoteAssetReserve, uint256 baseAssetReserve, uint256 timestamp);
    event CapChanged(uint256 maxHoldingBaseAsset, uint256 openInterestNotionalCap);
    event Shutdown(uint256 settlementPrice);
    event PriceFeedUpdated(address priceFeed);
    event ReservesAdjusted(uint256 quoteAssetReserve, uint256 baseAssetReserve, int256 totalPositionSize, int256 cumulativeNotional);

    //
    // MODIFIERS
    //
    modifier onlyOpen() {
        require(open, "AMM_C"); //amm was closed
        _;
    }

    modifier onlyCounterParty() {
        require(counterParty == _msgSender(), "AMM_NCP"); //not counterParty
        _;
    }

    //
    // FUNCTIONS
    //
    function initialize(
        uint256 _quoteAssetReserve,
        uint256 _baseAssetReserve,
        uint256 _tradeLimitRatio,
        uint256 _fundingPeriod,
        IPriceFeed _priceFeed,
        bytes32 _priceFeedKey,
        address _quoteAsset,
        uint256 _fluctuationLimitRatio,
        uint256 _tollRatio,
        uint256 _spreadRatio
    ) public initializer {
        require(
            _quoteAssetReserve != 0 &&
                _tradeLimitRatio != 0 &&
                _baseAssetReserve != 0 &&
                _fundingPeriod != 0 &&
                address(_priceFeed) != address(0) &&
                _quoteAsset != address(0),
            "AMM_III"
        ); //initial with invalid input
        _requireRatio(_fluctuationLimitRatio);
        _requireRatio(_tollRatio);
        _requireRatio(_spreadRatio);
        _requireRatio(_tradeLimitRatio);
        (bool success, bytes memory data) = _quoteAsset.call(abi.encodeWithSelector(bytes4(keccak256("decimals()"))));
        require(success && abi.decode(data, (uint8)) == 18, "AMM_NMD"); // not match decimal
        require(_priceFeed.decimals(_priceFeedKey) == 18, "AMM_NMD"); // not match decimal

        __Ownable_init();

        initMarginRatio = 0.2 ether; // 5x leverage
        maintenanceMarginRatio = 0.1 ether; // 10x leverage
        partialLiquidationRatio = 0.125 ether; // 1/8 of position size
        liquidationFeeRatio = 0.05 ether; // 5% - 1/2 of maintenance margin

        repegPriceGapRatio = 0; // 0%
        fundingCostCoverRate = 0.5 ether; // system covers 50% of normal funding payment when cost
        fundingRevenueTakeRate = 1 ether; // system take 100% of normal funding payment when revenue

        ptcKIncreaseMax = 1.005 ether; // 100.5% (0.5%) increase
        ptcKDecreaseMax = 0.99 ether; // 99% (1%) decrease

        quoteAssetReserve = _quoteAssetReserve;
        baseAssetReserve = _baseAssetReserve;
        tradeLimitRatio = _tradeLimitRatio;
        tollRatio = _tollRatio;
        spreadRatio = _spreadRatio;
        fluctuationLimitRatio = _fluctuationLimitRatio;
        fundingPeriod = _fundingPeriod;
        fundingBufferPeriod = _fundingPeriod / 2;
        spotPriceTwapInterval = 3 hours;
        priceFeedKey = _priceFeedKey;
        quoteAsset = IERC20(_quoteAsset);
        priceFeed = _priceFeed;
        reserveSnapshots[0] = ReserveSnapshot(quoteAssetReserve, baseAssetReserve, 0, _blockTimestamp(), _blockNumber());
        emit ReserveSnapshotted(quoteAssetReserve, baseAssetReserve, _blockTimestamp());
    }

    /**
     * @notice this function is called only when opening position
     * @dev Only clearingHouse can call this function
     * @param _dir ADD_TO_AMM, REMOVE_FROM_AMM
     * @param _amount quote asset amount
     * @param _isQuote whether or not amount is quote
     * @param _canOverFluctuationLimit if true, the impact of the price MUST be less than `fluctuationLimitRatio`
     */
    function swapInput(
        Dir _dir,
        uint256 _amount,
        bool _isQuote,
        bool _canOverFluctuationLimit
    )
        external
        override
        onlyOpen
        onlyCounterParty
        returns (
            uint256 quoteAssetAmount,
            int256 baseAssetAmount,
            uint256 spreadFee,
            uint256 tollFee
        )
    {
        uint256 uBaseAssetAmount;
        if (_isQuote) {
            quoteAssetAmount = _amount;
            uBaseAssetAmount = getQuotePrice(_dir, _amount);
        } else {
            quoteAssetAmount = getBasePrice(_dir, _amount);
            uBaseAssetAmount = _amount;
        }

        Dir dirOfQuote;
        if (_isQuote == (_dir == Dir.ADD_TO_AMM)) {
            // open long
            longPositionSize += uBaseAssetAmount;
            dirOfQuote = Dir.ADD_TO_AMM;
            baseAssetAmount = int256(uBaseAssetAmount);
        } else {
            // open short
            shortPositionSize += uBaseAssetAmount;
            dirOfQuote = Dir.REMOVE_FROM_AMM;
            baseAssetAmount = -1 * int256(uBaseAssetAmount);
        }
        spreadFee = quoteAssetAmount.mulD(spreadRatio);
        tollFee = quoteAssetAmount.mulD(tollRatio);

        _updateReserve(dirOfQuote, quoteAssetAmount, uBaseAssetAmount, _canOverFluctuationLimit);
        emit SwapInput(dirOfQuote, quoteAssetAmount, uBaseAssetAmount);
    }

    /**
     * @notice this function is called only when closing/reversing position
     * @dev only clearingHouse can call this function
     * @param _dir ADD_TO_AMM, REMOVE_FROM_AMM
     * @param _amount base asset amount
     * @param _isQuote whether or not amount is quote
     * @param _canOverFluctuationLimit if true, the impact of the price MUST be less than `fluctuationLimitRatio`
     */
    function swapOutput(
        Dir _dir,
        uint256 _amount,
        bool _isQuote,
        bool _canOverFluctuationLimit
    )
        external
        override
        onlyOpen
        onlyCounterParty
        returns (
            uint256 quoteAssetAmount,
            int256 baseAssetAmount,
            uint256 spreadFee,
            uint256 tollFee
        )
    {
        uint256 uBaseAssetAmount;
        if (_isQuote) {
            quoteAssetAmount = _amount;
            uBaseAssetAmount = getQuotePrice(_dir, _amount);
        } else {
            quoteAssetAmount = getBasePrice(_dir, _amount);
            uBaseAssetAmount = _amount;
        }

        Dir dirOfQuote;
        if (_isQuote == (_dir == Dir.ADD_TO_AMM)) {
            // close/reverse short
            uint256 _shortPositionSize = shortPositionSize;
            _shortPositionSize >= uBaseAssetAmount ? shortPositionSize = _shortPositionSize - uBaseAssetAmount : shortPositionSize = 0;
            dirOfQuote = Dir.ADD_TO_AMM;
            baseAssetAmount = int256(uBaseAssetAmount);
        } else {
            // close/reverse long
            uint256 _longPositionSize = longPositionSize;
            _longPositionSize >= uBaseAssetAmount ? longPositionSize = _longPositionSize - uBaseAssetAmount : longPositionSize = 0;
            dirOfQuote = Dir.REMOVE_FROM_AMM;
            baseAssetAmount = -1 * int256(uBaseAssetAmount);
        }
        spreadFee = quoteAssetAmount.mulD(spreadRatio);
        tollFee = quoteAssetAmount.mulD(tollRatio);

        _updateReserve(dirOfQuote, quoteAssetAmount, uBaseAssetAmount, _canOverFluctuationLimit);
        emit SwapOutput(dirOfQuote, quoteAssetAmount, uBaseAssetAmount);
    }

    /**
     * @notice update funding rate
     * @dev only allow to update while reaching `nextFundingTime`
     * @param _cap the limit of expense of funding payment
     * @return premiumFractionLong premium fraction for long of this period in 18 digits
     * @return premiumFractionShort premium fraction for short of this period in 18 digits
     * @return fundingPayment profit of insurance fund in funding payment
     */
    function settleFunding(uint256 _cap)
        external
        override
        onlyOpen
        onlyCounterParty
        returns (
            int256 premiumFractionLong,
            int256 premiumFractionShort,
            int256 fundingPayment
        )
    {
        require(_blockTimestamp() >= nextFundingTime, "AMM_SFTE"); //settle funding too early
        uint256 underlyingPrice;
        bool notPayable;
        (notPayable, premiumFractionLong, premiumFractionShort, fundingPayment, underlyingPrice) = getFundingPaymentEstimation(_cap);
        if (notPayable) {
            _implShutdown();
        }
        // positive fundingPayment is revenue to system, otherwise cost to system
        emit FundingRateUpdated(
            premiumFractionLong.divD(underlyingPrice.toInt()),
            premiumFractionShort.divD(underlyingPrice.toInt()),
            underlyingPrice,
            fundingPayment
        );

        // in order to prevent multiple funding settlement during very short time after network congestion
        uint256 minNextValidFundingTime = _blockTimestamp() + fundingBufferPeriod;

        // floor((nextFundingTime + fundingPeriod) / 3600) * 3600
        uint256 nextFundingTimeOnHourStart = ((nextFundingTime + fundingPeriod) / (1 hours)) * (1 hours);

        // max(nextFundingTimeOnHourStart, minNextValidFundingTime)
        nextFundingTime = nextFundingTimeOnHourStart > minNextValidFundingTime ? nextFundingTimeOnHourStart : minNextValidFundingTime;
    }

    /**
     * @notice check if repeg can be done and get the cost and reserves of formulaic repeg
     * @param _budget the budget available for repeg
     * @return isAdjustable if true, curve can be adjustable by repeg
     * @return cost the amount of cost of repeg, negative means profit of system
     * @return newQuoteAssetReserve the new quote asset reserve by repeg
     * @return newBaseAssetReserve the new base asset reserve by repeg
     */
    function repegCheck(uint256 _budget)
        external
        override
        onlyCounterParty
        returns (
            bool isAdjustable,
            int256 cost,
            uint256 newQuoteAssetReserve,
            uint256 newBaseAssetReserve
        )
    {
        if (open && adjustable) {
            uint256 _repegFlag = repegFlag;
            (bool result, uint256 marketPrice, uint256 oraclePrice) = isOverSpreadLimit();
            if (result) {
                _repegFlag += 1;
            } else {
                _repegFlag = 0;
            }
            int256 _positionSize = getBaseAssetDelta();
            uint256 targetPrice;
            if (_positionSize == 0) {
                targetPrice = oraclePrice;
            } else if (_repegFlag >= MIN_NUM_REPEG_FLAG) {
                targetPrice = oraclePrice > marketPrice
                    ? oraclePrice.mulD(1 ether - repegPriceGapRatio)
                    : oraclePrice.mulD(1 ether + repegPriceGapRatio);
            }
            if (targetPrice != 0) {
                uint256 _quoteAssetReserve = quoteAssetReserve; //to optimize gas cost
                uint256 _baseAssetReserve = baseAssetReserve; //to optimize gas cost
                (newQuoteAssetReserve, newBaseAssetReserve) = AmmMath.calcReservesAfterRepeg(
                    _quoteAssetReserve,
                    _baseAssetReserve,
                    targetPrice,
                    _positionSize
                );
                cost = AmmMath.calcCostForAdjustReserves(
                    _quoteAssetReserve,
                    _baseAssetReserve,
                    _positionSize,
                    newQuoteAssetReserve,
                    newBaseAssetReserve
                );
                if (cost > 0 && uint256(cost) > _budget) {
                    isAdjustable = false;
                } else {
                    isAdjustable = true;
                }
            }
            repegFlag = uint8(_repegFlag);
        }
    }

    /**
     * Repeg both reserves in case of repegging and k-adjustment
     */
    function adjust(uint256 _quoteAssetReserve, uint256 _baseAssetReserve) external onlyCounterParty {
        require(_quoteAssetReserve != 0, "AMM_ZQ"); //quote asset reserve cannot be 0
        require(_baseAssetReserve != 0, "AMM_ZB"); //base asset reserve cannot be 0
        quoteAssetReserve = _quoteAssetReserve;
        baseAssetReserve = _baseAssetReserve;
        _addReserveSnapshot();
        emit ReservesAdjusted(quoteAssetReserve, baseAssetReserve, getBaseAssetDelta(), cumulativeNotional);
    }

    /**
     * @notice shutdown amm,
     * @dev only `globalShutdown` or owner can call this function
     * The price calculation is in `globalShutdown`.
     */
    function shutdown() external override {
        require(_msgSender() == owner() || _msgSender() == globalShutdown, "AMM_NONG"); //not owner nor globalShutdown
        _implShutdown();
    }

    /**
     * @notice set init margin ratio, should be bigger than mm ratio
     * @dev only owner can call
     * @param _initMarginRatio new maintenance margin ratio in 18 digits
     */
    function setInitMarginRatio(uint256 _initMarginRatio) external onlyOwner {
        _requireNonZeroInput(_initMarginRatio);
        _requireRatio(_initMarginRatio);
        require(maintenanceMarginRatio < _initMarginRatio, "AMM_WIMR"); // wrong init margin ratio
        initMarginRatio = _initMarginRatio;
    }

    /**
     * @notice set maintenance margin ratio, should be smaller than initMarginRatio
     * @dev only owner can call
     * @param _maintenanceMarginRatio new maintenance margin ratio in 18 digits
     */
    function setMaintenanceMarginRatio(uint256 _maintenanceMarginRatio) external onlyOwner {
        _requireNonZeroInput(_maintenanceMarginRatio);
        _requireRatio(_maintenanceMarginRatio);
        require(_maintenanceMarginRatio < initMarginRatio, "AMM_WMMR"); // wrong maintenance margin ratio
        maintenanceMarginRatio = _maintenanceMarginRatio;
    }

    /**
     * @notice set liquidation fee ratio, shouldn't be bigger than mm ratio
     * @dev only owner can call
     * @param _liquidationFeeRatio new liquidation fee ratio in 18 digits
     */
    function setLiquidationFeeRatio(uint256 _liquidationFeeRatio) external onlyOwner {
        _requireNonZeroInput(_liquidationFeeRatio);
        _requireRatio(_liquidationFeeRatio);
        require(_liquidationFeeRatio <= maintenanceMarginRatio, "AMM_WLFR"); // wrong liquidation fee ratio
        liquidationFeeRatio = _liquidationFeeRatio;
    }

    /**
     * @notice set the margin ratio after deleveraging
     * @dev only owner can call
     */
    function setPartialLiquidationRatio(uint256 _ratio) external onlyOwner {
        _requireRatio(_ratio);
        partialLiquidationRatio = _ratio;
    }

    /**
     * @notice set counter party
     * @dev only owner can call this function
     * @param _counterParty address of counter party
     */
    function setCounterParty(address _counterParty) external onlyOwner {
        _requireNonZeroAddress(_counterParty);
        counterParty = _counterParty;
    }

    /**
     * @notice set `globalShutdown`
     * @dev only owner can call this function
     * @param _globalShutdown address of `globalShutdown`
     */
    function setGlobalShutdown(address _globalShutdown) external onlyOwner {
        _requireNonZeroAddress(_globalShutdown);
        globalShutdown = _globalShutdown;
    }

    /**
     * @notice set fluctuation limit rate. Default value is `1 / max leverage`
     * @dev only owner can call this function
     * @param _fluctuationLimitRatio fluctuation limit rate in 18 digits, 0 means skip the checking
     */
    function setFluctuationLimitRatio(uint256 _fluctuationLimitRatio) external onlyOwner {
        _requireRatio(_fluctuationLimitRatio);
        fluctuationLimitRatio = _fluctuationLimitRatio;
    }

    /**
     * @notice set time interval for twap calculation, default is 1 hour
     * @dev only owner can call this function
     * @param _interval time interval in seconds
     */
    function setSpotPriceTwapInterval(uint256 _interval) external onlyOwner {
        require(_interval != 0, "AMM_ZI"); // zero interval
        require(_interval <= 24 * 3600, "AMM_GTO"); // greater than 1 day
        spotPriceTwapInterval = _interval;
    }

    /**
     * @notice set `open` flag. Amm is open to trade if `open` is true. Default is false.
     * @dev only owner can call this function
     * @param _open open to trade is true, otherwise is false.
     */
    function setOpen(bool _open) external onlyOwner {
        if (open == _open) return;

        open = _open;
        if (_open) {
            nextFundingTime = ((_blockTimestamp() + fundingPeriod) / (1 hours)) * (1 hours);
        }
    }

    /**
     * @notice set `adjustable` flag. Amm is open to formulaic repeg and K adjustment if `adjustable` is true. Default is false.
     * @dev only owner can call this function
     * @param _adjustable open to formulaic repeg and K adjustment is true, otherwise is false.
     */
    function setAdjustable(bool _adjustable) external onlyOwner {
        if (adjustable == _adjustable) return;
        adjustable = _adjustable;
    }

    /**
     * @notice set `canLowerK` flag. Amm is open to decrease K adjustment if `canLowerK` is true. Default is false.
     * @dev only owner can call this function
     * @param _canLowerK open to decrease K adjustment is true, otherwise is false.
     */
    function setCanLowerK(bool _canLowerK) external onlyOwner {
        if (canLowerK == _canLowerK) return;
        canLowerK = _canLowerK;
    }

    /**
     * @notice set new toll ratio
     * @dev only owner can call
     * @param _tollRatio new toll ratio in 18 digits
     */
    function setTollRatio(uint256 _tollRatio) external onlyOwner {
        _requireRatio(_tollRatio);
        tollRatio = _tollRatio;
    }

    /**
     * @notice set new spread ratio
     * @dev only owner can call
     * @param _spreadRatio new toll spread in 18 digits
     */
    function setSpreadRatio(uint256 _spreadRatio) external onlyOwner {
        _requireRatio(_spreadRatio);
        spreadRatio = _spreadRatio;
    }

    /**
     * @notice set priceFee address
     * @dev only owner can call
     * @param _priceFeed new price feed for this AMM
     */
    function setPriceFeed(IPriceFeed _priceFeed) external onlyOwner {
        _requireNonZeroAddress(address(_priceFeed));
        priceFeed = _priceFeed;
        emit PriceFeedUpdated(address(priceFeed));
    }

    function setRepegPriceGapRatio(uint256 _ratio) external onlyOwner {
        _requireRatio(_ratio);
        repegPriceGapRatio = _ratio;
    }

    function setFundingCostCoverRate(uint256 _rate) external onlyOwner {
        _requireRatio(_rate);
        fundingCostCoverRate = _rate;
    }

    function setFundingRevenueTakeRate(uint256 _rate) external onlyOwner {
        _requireRatio(_rate);
        fundingRevenueTakeRate = _rate;
    }

    function setKIncreaseMax(uint256 _rate) external onlyOwner {
        require(_rate > 1 ether, "AMM_IIR"); // invalid increase ratio
        ptcKIncreaseMax = _rate;
    }

    function setKDecreaseMax(uint256 _rate) external onlyOwner {
        require(_rate < 1 ether && _rate > 0, "AMM_IDR"); // invalid decrease ratio
        ptcKDecreaseMax = _rate;
    }

    //
    // VIEW FUNCTIONS
    //

    /**
     * @notice get the cost and reserves when adjust k
     * @param _budget the budget available for adjust
     * @return isAdjustable if true, curve can be adjustable by adjust k
     * @return cost the amount of cost of adjust k
     * @return newQuoteAssetReserve the new quote asset reserve by adjust k
     * @return newBaseAssetReserve the new base asset reserve by adjust k
     */

    function getFormulaicUpdateKResult(int256 _budget)
        external
        view
        returns (
            bool isAdjustable,
            int256 cost,
            uint256 newQuoteAssetReserve,
            uint256 newBaseAssetReserve
        )
    {
        if (open && adjustable && (_budget > 0 || (_budget < 0 && canLowerK))) {
            uint256 _quoteAssetReserve = quoteAssetReserve; //to optimize gas cost
            uint256 _baseAssetReserve = baseAssetReserve; //to optimize gas cost
            int256 _positionSize = getBaseAssetDelta(); //to optimize gas cost
            (uint256 scaleNum, uint256 scaleDenom) = AmmMath.calculateBudgetedKScale(
                AmmMath.BudgetedKScaleCalcParams({
                    quoteAssetReserve: _quoteAssetReserve,
                    baseAssetReserve: _baseAssetReserve,
                    budget: _budget,
                    positionSize: _positionSize,
                    ptcKIncreaseMax: ptcKIncreaseMax,
                    ptcKDecreaseMax: ptcKDecreaseMax
                })
            );
            if (scaleNum == scaleDenom || scaleDenom == 0 || scaleNum == 0) {
                isAdjustable = false;
            } else {
                newQuoteAssetReserve = Math.mulDiv(_quoteAssetReserve, scaleNum, scaleDenom);
                newBaseAssetReserve = Math.mulDiv(_baseAssetReserve, scaleNum, scaleDenom);
                isAdjustable = _positionSize >= 0 || newBaseAssetReserve > _positionSize.abs();
                if (isAdjustable) {
                    cost = AmmMath.calcCostForAdjustReserves(
                        _quoteAssetReserve,
                        _baseAssetReserve,
                        _positionSize,
                        newQuoteAssetReserve,
                        newBaseAssetReserve
                    );
                }
            }
        }
    }

    function getMaxKDecreaseRevenue(uint256 _quoteAssetReserve, uint256 _baseAssetReserve) external view override returns (int256 revenue) {
        if (open && adjustable && canLowerK) {
            uint256 _ptcKDecreaseMax = ptcKDecreaseMax;
            int256 _positionSize = getBaseAssetDelta();
            if (_positionSize >= 0 || _baseAssetReserve.mulD(_ptcKDecreaseMax) > _positionSize.abs()) {
                // decreasing cost is always negative (profit)
                revenue =
                    (-1) *
                    AmmMath.calcCostForAdjustReserves(
                        _quoteAssetReserve,
                        _baseAssetReserve,
                        _positionSize,
                        _quoteAssetReserve.mulD(_ptcKDecreaseMax),
                        _baseAssetReserve.mulD(_ptcKDecreaseMax)
                    );
            }
        }
    }

    function isOverFluctuationLimit(Dir _dirOfBase, uint256 _baseAssetAmount) external view override returns (bool) {
        // Skip the check if the limit is 0
        if (fluctuationLimitRatio == 0) {
            return false;
        }

        (uint256 upperLimit, uint256 lowerLimit) = _getPriceBoundariesOfLastBlock();

        uint256 quoteAssetExchanged = getBasePrice(_dirOfBase, _baseAssetAmount);
        uint256 price = (_dirOfBase == Dir.REMOVE_FROM_AMM)
            ? (quoteAssetReserve + quoteAssetExchanged).divD(baseAssetReserve - _baseAssetAmount)
            : (quoteAssetReserve - quoteAssetExchanged).divD(baseAssetReserve + _baseAssetAmount);

        if (price <= upperLimit && price >= lowerLimit) {
            return false;
        }
        return true;
    }

    /**
     * @notice get input twap amount.
     * returns how many base asset you will get with the input quote amount based on twap price.
     * @param _dirOfQuote ADD_TO_AMM for long, REMOVE_FROM_AMM for short.
     * @param _quoteAssetAmount quote asset amount
     * @return base asset amount
     */
    function getQuoteTwap(Dir _dirOfQuote, uint256 _quoteAssetAmount) public view override returns (uint256) {
        return _implGetInputAssetTwapPrice(_dirOfQuote, _quoteAssetAmount, QuoteAssetDir.QUOTE_IN, 15 minutes);
    }

    /**
     * @notice get output twap amount.
     * return how many quote asset you will get with the input base amount on twap price.
     * @param _dirOfBase ADD_TO_AMM for short, REMOVE_FROM_AMM for long, opposite direction from `getQuoteTwap`.
     * @param _baseAssetAmount base asset amount
     * @return quote asset amount
     */
    function getBaseTwap(Dir _dirOfBase, uint256 _baseAssetAmount) public view override returns (uint256) {
        return _implGetInputAssetTwapPrice(_dirOfBase, _baseAssetAmount, QuoteAssetDir.QUOTE_OUT, 15 minutes);
    }

    /**
     * @notice get input amount. returns how many base asset you will get with the input quote amount.
     * @param _dirOfQuote ADD_TO_AMM for long, REMOVE_FROM_AMM for short.
     * @param _quoteAssetAmount quote asset amount
     * @return base asset amount
     */
    function getQuotePrice(Dir _dirOfQuote, uint256 _quoteAssetAmount) public view override returns (uint256) {
        return getQuotePriceWithReserves(_dirOfQuote, _quoteAssetAmount, quoteAssetReserve, baseAssetReserve);
    }

    /**
     * @notice get output price. return how many quote asset you will get with the input base amount
     * @param _dirOfBase ADD_TO_AMM for short, REMOVE_FROM_AMM for long, opposite direction from `getInput`.
     * @param _baseAssetAmount base asset amount
     * @return quote asset amount
     */
    function getBasePrice(Dir _dirOfBase, uint256 _baseAssetAmount) public view override returns (uint256) {
        return getBasePriceWithReserves(_dirOfBase, _baseAssetAmount, quoteAssetReserve, baseAssetReserve);
    }

    /**
     * @notice get underlying price provided by oracle
     * @return underlying price
     */
    function getUnderlyingPrice() public view override returns (uint256) {
        return uint256(priceFeed.getPrice(priceFeedKey));
    }

    /**
     * @notice get underlying twap price provided by oracle
     * @return underlying price
     */
    function getUnderlyingTwapPrice(uint256 _intervalInSeconds) public view returns (uint256) {
        return uint256(priceFeed.getTwapPrice(priceFeedKey, _intervalInSeconds));
    }

    /**
     * @notice get spot price based on current quote/base asset reserve.
     * @return spot price
     */
    function getSpotPrice() public view override returns (uint256) {
        return quoteAssetReserve.divD(baseAssetReserve);
    }

    /**
     * @notice get twap price
     */
    function getTwapPrice(uint256 _intervalInSeconds) public view returns (uint256) {
        return _calcTwap(_intervalInSeconds);
    }

    /**
     * @notice get current quote/base asset reserve.
     * @return (quote asset reserve, base asset reserve)
     */
    function getReserve() public view returns (uint256, uint256) {
        return (quoteAssetReserve, baseAssetReserve);
    }

    function getCumulativeNotional() public view override returns (int256) {
        return cumulativeNotional;
    }

    function getSettlementPrice() public view override returns (uint256) {
        return settlementPrice;
    }

    function getBaseAssetDelta() public view override returns (int256) {
        return longPositionSize.toInt() - shortPositionSize.toInt();
    }

    function isOverSpreadLimit()
        public
        view
        override
        returns (
            bool result,
            uint256 marketPrice,
            uint256 oraclePrice
        )
    {
        (result, marketPrice, oraclePrice) = isOverSpread(MAX_ORACLE_SPREAD_RATIO);
    }

    function isOverSpread(uint256 _limit)
        public
        view
        virtual
        override
        returns (
            bool result,
            uint256 marketPrice,
            uint256 oraclePrice
        )
    {
        oraclePrice = getUnderlyingPrice();
        require(oraclePrice > 0, "AMM_ZOP"); //zero oracle price
        marketPrice = getSpotPrice();
        uint256 oracleSpreadRatioAbs = (marketPrice.toInt() - oraclePrice.toInt()).divD(oraclePrice.toInt()).abs();

        result = oracleSpreadRatioAbs >= _limit ? true : false;
    }

    /**
     * @notice calculate total fee (including toll and spread) by input quoteAssetAmount
     * @param _quoteAssetAmount quoteAssetAmount
     * @return total tx fee
     */
    function calcFee(uint256 _quoteAssetAmount) public view override returns (uint256, uint256) {
        return (_quoteAssetAmount.mulD(tollRatio), _quoteAssetAmount.mulD(spreadRatio));
    }

    /*       plus/minus 1 while the amount is not dividable
     *
     *        getQuotePrice                         getBasePrice
     *
     *     ＡＤＤ      (amount - 1)              (amount + 1)   ＲＥＭＯＶＥ
     *      ◥◤            ▲                         |             ◢◣
     *      ◥◤  ------->  |                         ▼  <--------  ◢◣
     *    -------      -------                   -------        -------
     *    |  Q  |      |  B  |                   |  Q  |        |  B  |
     *    -------      -------                   -------        -------
     *      ◥◤  ------->  ▲                         |  <--------  ◢◣
     *      ◥◤            |                         ▼             ◢◣
     *   ＲＥＭＯＶＥ  (amount + 1)              (amount - 1)      ＡＤＤ
     **/

    function getQuotePriceWithReserves(
        Dir _dirOfQuote,
        uint256 _quoteAssetAmount,
        uint256 _quoteAssetPoolAmount,
        uint256 _baseAssetPoolAmount
    ) public pure override returns (uint256) {
        if (_quoteAssetAmount == 0) {
            return 0;
        }

        bool isAddToAmm = _dirOfQuote == Dir.ADD_TO_AMM;
        uint256 baseAssetAfter;
        uint256 quoteAssetAfter;
        uint256 baseAssetBought;
        if (isAddToAmm) {
            quoteAssetAfter = _quoteAssetPoolAmount + _quoteAssetAmount;
        } else {
            quoteAssetAfter = _quoteAssetPoolAmount - _quoteAssetAmount;
        }
        require(quoteAssetAfter != 0, "AMM_ZQAA"); //zero quote asset after

        baseAssetAfter = Math.mulDiv(_quoteAssetPoolAmount, _baseAssetPoolAmount, quoteAssetAfter, Math.Rounding.Up);
        baseAssetBought = (baseAssetAfter.toInt() - _baseAssetPoolAmount.toInt()).abs();

        return baseAssetBought;
    }

    function getBasePriceWithReserves(
        Dir _dirOfBase,
        uint256 _baseAssetAmount,
        uint256 _quoteAssetPoolAmount,
        uint256 _baseAssetPoolAmount
    ) public pure override returns (uint256) {
        if (_baseAssetAmount == 0) {
            return 0;
        }

        bool isAddToAmm = _dirOfBase == Dir.ADD_TO_AMM;
        uint256 quoteAssetAfter;
        uint256 baseAssetAfter;
        uint256 quoteAssetSold;

        if (isAddToAmm) {
            baseAssetAfter = _baseAssetPoolAmount + _baseAssetAmount;
        } else {
            baseAssetAfter = _baseAssetPoolAmount - _baseAssetAmount;
        }
        require(baseAssetAfter != 0, "AMM_ZBAA"); //zero base asset after

        quoteAssetAfter = Math.mulDiv(_quoteAssetPoolAmount, _baseAssetPoolAmount, baseAssetAfter, Math.Rounding.Up);
        quoteAssetSold = (quoteAssetAfter.toInt() - _quoteAssetPoolAmount.toInt()).abs();

        return quoteAssetSold;
    }

    function getFundingPaymentEstimation(uint256 _cap)
        public
        view
        override
        returns (
            bool notPayable,
            int256 premiumFractionLong,
            int256 premiumFractionShort,
            int256 fundingPayment,
            uint256 underlyingPrice
        )
    {
        // premium = twapMarketPrice - twapIndexPrice
        // timeFraction = fundingPeriod(3 hour) / 1 day
        // premiumFraction = premium * timeFraction
        underlyingPrice = getUnderlyingTwapPrice(spotPriceTwapInterval);
        int256 premiumFraction = ((getTwapPrice(spotPriceTwapInterval).toInt() - underlyingPrice.toInt()) * fundingPeriod.toInt()) /
            int256(1 days);
        int256 positionSize = getBaseAssetDelta();
        // funding payment = premium fraction * position
        // eg. if alice takes 10 long position, totalPositionSize = 10
        // if premiumFraction is positive: long pay short, amm get positive funding payment
        // if premiumFraction is negative: short pay long, amm get negative funding payment
        // if totalPositionSize.side * premiumFraction > 0, funding payment is positive which means profit
        int256 normalFundingPayment = premiumFraction.mulD(positionSize);

        // dynamic funding rate formula
        // premiumFractionLong  = premiumFraction * (2*shortSize + a*positionSize) / (longSize + shortSize)
        // premiumFractionShort = premiumFraction * (2*longSize  - a*positionSize) / (longSize + shortSize)
        int256 _longPositionSize = int256(longPositionSize);
        int256 _shortPositionSize = int256(shortPositionSize);
        int256 _fundingRevenueTakeRate = int256(fundingRevenueTakeRate);
        int256 _fundingCostCoverRate = int256(fundingCostCoverRate);

        if (normalFundingPayment > 0 && _fundingRevenueTakeRate < 1 ether && _longPositionSize + _shortPositionSize != 0) {
            // when the normal funding payment is revenue and daynamic rate is available, system takes profit partially
            fundingPayment = normalFundingPayment.mulD(_fundingRevenueTakeRate);
            int256 sign = premiumFraction >= 0 ? int256(1) : int256(-1);
            premiumFractionLong =
                int256(
                    Math.mulDiv(
                        premiumFraction.abs(),
                        uint256(_shortPositionSize * 2 + positionSize.mulD(_fundingRevenueTakeRate)),
                        uint256(_longPositionSize + _shortPositionSize)
                    )
                ) *
                sign;
            premiumFractionShort =
                int256(
                    Math.mulDiv(
                        premiumFraction.abs(),
                        uint256(_longPositionSize * 2 - positionSize.mulD(_fundingRevenueTakeRate)),
                        uint256(_longPositionSize + _shortPositionSize)
                    )
                ) *
                sign;
        } else if (normalFundingPayment < 0 && _fundingCostCoverRate < 1 ether && _longPositionSize + _shortPositionSize != 0) {
            // when the normal funding payment is cost and daynamic rate is available, system covers partially
            fundingPayment = normalFundingPayment.mulD(_fundingCostCoverRate);
            int256 sign = premiumFraction >= 0 ? int256(1) : int256(-1);
            if (uint256(-fundingPayment) > _cap) {
                // when the funding payment that system covers is greater than the cap, then not pay funding and shutdown amm
                fundingPayment = 0;
                notPayable = true;
            } else {
                premiumFractionLong =
                    int256(
                        Math.mulDiv(
                            premiumFraction.abs(),
                            uint256(_shortPositionSize * 2 + positionSize.mulD(_fundingCostCoverRate)),
                            uint256(_longPositionSize + _shortPositionSize)
                        )
                    ) *
                    sign;
                premiumFractionShort =
                    int256(
                        Math.mulDiv(
                            premiumFraction.abs(),
                            uint256(_longPositionSize * 2 - positionSize.mulD(_fundingCostCoverRate)),
                            uint256(_longPositionSize + _shortPositionSize)
                        )
                    ) *
                    sign;
            }
        } else {
            fundingPayment = normalFundingPayment;
            // if expense of funding payment is greater than cap amount, then not pay funding and shutdown amm
            if (fundingPayment < 0 && uint256(-fundingPayment) > _cap) {
                fundingPayment = 0;
                notPayable = true;
            } else {
                premiumFractionLong = premiumFraction;
                premiumFractionShort = premiumFraction;
            }
        }
    }

    function _addReserveSnapshot() internal {
        uint256 currentBlock = _blockNumber();
        uint16 _latestReserveSnapshotIndex = latestReserveSnapshotIndex;
        ReserveSnapshot storage latestSnapshot = reserveSnapshots[_latestReserveSnapshotIndex];
        // update values in snapshot if in the same block
        if (currentBlock == latestSnapshot.blockNumber) {
            latestSnapshot.quoteAssetReserve = quoteAssetReserve;
            latestSnapshot.baseAssetReserve = baseAssetReserve;
        } else {
            // _latestReserveSnapshotIndex is uint16, so overflow means 65535+1=0
            unchecked {
                _latestReserveSnapshotIndex++;
            }
            latestReserveSnapshotIndex = _latestReserveSnapshotIndex;
            reserveSnapshots[_latestReserveSnapshotIndex] = ReserveSnapshot(
                quoteAssetReserve,
                baseAssetReserve,
                latestSnapshot.cumulativeTWPBefore +
                    latestSnapshot.quoteAssetReserve.divD(latestSnapshot.baseAssetReserve) *
                    (_blockTimestamp() - latestSnapshot.timestamp),
                _blockTimestamp(),
                currentBlock
            );
        }
        emit ReserveSnapshotted(quoteAssetReserve, baseAssetReserve, _blockTimestamp());
    }

    // the direction is in quote asset
    function _updateReserve(
        Dir _dirOfQuote,
        uint256 _quoteAssetAmount,
        uint256 _baseAssetAmount,
        bool _canOverFluctuationLimit
    ) internal {
        uint256 _quoteAssetReserve = quoteAssetReserve;
        uint256 _baseAssetReserve = baseAssetReserve;
        // check if it's over fluctuationLimitRatio
        // this check should be before reserves being updated
        _checkIsOverBlockFluctuationLimit(
            _dirOfQuote,
            _quoteAssetAmount,
            _baseAssetAmount,
            _quoteAssetReserve,
            _baseAssetReserve,
            _canOverFluctuationLimit
        );

        if (_dirOfQuote == Dir.ADD_TO_AMM) {
            require(_baseAssetReserve.mulD(tradeLimitRatio) >= _baseAssetAmount, "AMM_OTL"); //over trading limit
            quoteAssetReserve = _quoteAssetReserve + _quoteAssetAmount;
            baseAssetReserve = _baseAssetReserve - _baseAssetAmount;
            cumulativeNotional = cumulativeNotional + _quoteAssetAmount.toInt();
        } else {
            require(_quoteAssetReserve.mulD(tradeLimitRatio) >= _quoteAssetAmount, "AMM_OTL"); //over trading limit
            quoteAssetReserve = _quoteAssetReserve - _quoteAssetAmount;
            baseAssetReserve = _baseAssetReserve + _baseAssetAmount;
            cumulativeNotional = cumulativeNotional - _quoteAssetAmount.toInt();
        }

        // _addReserveSnapshot must be after checking price fluctuation
        _addReserveSnapshot();
    }

    function _implGetInputAssetTwapPrice(
        Dir _dirOfQuote,
        uint256 _assetAmount,
        QuoteAssetDir _inOut,
        uint256 _interval
    ) internal view returns (uint256) {
        TwapPriceCalcParams memory params;
        params.snapshotIndex = latestReserveSnapshotIndex;
        params.asset.dir = _dirOfQuote;
        params.asset.assetAmount = _assetAmount;
        params.asset.inOrOut = _inOut;
        return _calcAssetTwap(params, _interval);
    }

    function _calcAssetTwap(TwapPriceCalcParams memory _params, uint256 _interval) internal view returns (uint256) {
        uint256 baseTimestamp = _blockTimestamp() - _interval;
        uint256 previousTimestamp = _blockTimestamp();
        uint256 i;
        ReserveSnapshot memory currentSnapshot;
        uint256 currentPrice;
        uint256 period;
        uint256 weightedPrice;
        uint256 timeFraction;
        // runs at most 900, due to have 15mins interval
        for (i; i < 65536; ) {
            currentSnapshot = reserveSnapshots[_params.snapshotIndex];
            // not enough history
            if (currentSnapshot.timestamp == 0) {
                return period == 0 ? currentPrice : weightedPrice / period;
            }
            currentPrice = _getAssetPriceWithSpecificSnapshot(currentSnapshot, _params);

            // check if current round timestamp is earlier than target timestamp
            if (currentSnapshot.timestamp <= baseTimestamp) {
                // weighted time period will be (target timestamp - previous timestamp). For example,
                // now is 1000, _interval is 100, then target timestamp is 900. If timestamp of current round is 970,
                // and timestamp of NEXT round is 880, then the weighted time period will be (970 - 900) = 70,
                // instead of (970 - 880)
                weightedPrice = weightedPrice + (currentPrice * (previousTimestamp - baseTimestamp));
                break;
            }
            timeFraction = previousTimestamp - currentSnapshot.timestamp;
            weightedPrice = weightedPrice + (currentPrice * timeFraction);
            period = period + timeFraction;
            previousTimestamp = currentSnapshot.timestamp;
            unchecked {
                _params.snapshotIndex = _params.snapshotIndex - 1;
                i++;
            }
        }
        // if snapshot history is too short
        if (i == 256) {
            return weightedPrice / period;
        } else {
            return weightedPrice / _interval;
        }
    }

    function _getAssetPriceWithSpecificSnapshot(ReserveSnapshot memory snapshot, TwapPriceCalcParams memory params)
        internal
        pure
        virtual
        returns (uint256)
    {
        if (params.asset.assetAmount == 0) {
            return 0;
        }
        if (params.asset.inOrOut == QuoteAssetDir.QUOTE_IN) {
            return
                getQuotePriceWithReserves(
                    params.asset.dir,
                    params.asset.assetAmount,
                    snapshot.quoteAssetReserve,
                    snapshot.baseAssetReserve
                );
        } else if (params.asset.inOrOut == QuoteAssetDir.QUOTE_OUT) {
            return
                getBasePriceWithReserves(params.asset.dir, params.asset.assetAmount, snapshot.quoteAssetReserve, snapshot.baseAssetReserve);
        }
        revert("AMM_NOMP"); //not supported option for market price for a specific snapshot
    }

    function _calcTwap(uint256 interval) internal view returns (uint256) {
        ReserveSnapshot memory latestSnapshot = reserveSnapshots[latestReserveSnapshotIndex];
        uint256 currentTimestamp = _blockTimestamp();
        uint256 targetTimestamp = currentTimestamp - interval;
        ReserveSnapshot memory beforeOrAt = _getBeforeOrAtReserveSnapshots(targetTimestamp);
        uint256 currentCumulativePrice = latestSnapshot.cumulativeTWPBefore +
            latestSnapshot.quoteAssetReserve.divD(latestSnapshot.baseAssetReserve) *
            (currentTimestamp - latestSnapshot.timestamp);

        //
        //                   beforeOrAt
        //      ------------------+-------------+---------------
        //                <-------|             |
        // case 1       targetTimestamp         |
        // case 2                          targetTimestamp
        //
        uint256 targetCumulativePrice;
        // case1. not enough historical data or just enough (`==` case)
        if (targetTimestamp <= beforeOrAt.timestamp) {
            targetTimestamp = beforeOrAt.timestamp;
            targetCumulativePrice = beforeOrAt.cumulativeTWPBefore;
        }
        // case2. enough historical data
        else {
            uint256 targetTimeDelta = targetTimestamp - beforeOrAt.timestamp;
            targetCumulativePrice =
                beforeOrAt.cumulativeTWPBefore +
                beforeOrAt.quoteAssetReserve.divD(beforeOrAt.baseAssetReserve) *
                targetTimeDelta;
        }
        if (currentTimestamp == targetTimestamp) {
            return beforeOrAt.quoteAssetReserve.divD(beforeOrAt.baseAssetReserve);
        } else {
            return (currentCumulativePrice - targetCumulativePrice) / (currentTimestamp - targetTimestamp);
        }
    }

    /**
     * @dev searches the reserve snapshot array and returns the snapshot of which timestamp is just before or equals to the target timestamp
     * if no such one exists, returns the oldest snapshot
     * time complexity O(log n) due to binary search algorithm, max len of array is 2**16, so max loops is 16
     */
    function _getBeforeOrAtReserveSnapshots(uint256 targetTimestamp) internal view returns (ReserveSnapshot memory beforeOrAt) {
        uint256 _latestReserveSnapshotIndex = uint256(latestReserveSnapshotIndex);
        uint256 low = _latestReserveSnapshotIndex + 1;
        uint256 high = _latestReserveSnapshotIndex | (uint256(1) << 16);
        uint256 mid;
        if (reserveSnapshots[uint16(low)].timestamp == 0) {
            low = 0;
            high = high ^ (uint256(1) << 16);
        }

        while (low < high) {
            unchecked {
                mid = (low + high) / 2;
            }

            // Note that mid will always be strictly less than high (i.e. it will be a valid array index)
            // because it is derived from integer division.
            if (reserveSnapshots[uint16(mid)].timestamp > targetTimestamp) {
                high = mid;
            } else {
                unchecked {
                    low = mid + 1;
                }
            }
        }

        if (low > 0 && low != _latestReserveSnapshotIndex + 1 && reserveSnapshots[uint16(low)].timestamp > targetTimestamp) {
            beforeOrAt = reserveSnapshots[uint16(low - 1)];
        } else {
            beforeOrAt = reserveSnapshots[uint16(low)];
        }
    }

    function _getPriceBoundariesOfLastBlock() internal view returns (uint256, uint256) {
        uint16 _latestReserveSnapshotIndex = latestReserveSnapshotIndex;
        ReserveSnapshot memory latestSnapshot = reserveSnapshots[_latestReserveSnapshotIndex];
        // if the latest snapshot is the same as current block and it is not the initial snapshot, get the previous one
        if (latestSnapshot.blockNumber == _blockNumber()) {
            // underflow means 0-1=65535
            unchecked {
                _latestReserveSnapshotIndex--;
            }
            if (reserveSnapshots[_latestReserveSnapshotIndex].timestamp != 0)
                latestSnapshot = reserveSnapshots[_latestReserveSnapshotIndex];
        }

        uint256 lastPrice = latestSnapshot.quoteAssetReserve.divD(latestSnapshot.baseAssetReserve);
        uint256 upperLimit = lastPrice.mulD(1 ether + fluctuationLimitRatio);
        uint256 lowerLimit = lastPrice.mulD(1 ether - fluctuationLimitRatio);
        return (upperLimit, lowerLimit);
    }

    /**
     * @notice there can only be one tx in a block can skip the fluctuation check
     *         otherwise, some positions can never be closed or liquidated
     * @param _canOverFluctuationLimit if true, can skip fluctuation check for once; else, can never skip
     */
    function _checkIsOverBlockFluctuationLimit(
        Dir _dirOfQuote,
        uint256 _quoteAssetAmount,
        uint256 _baseAssetAmount,
        uint256 _quoteAssetReserve,
        uint256 _baseAssetReserve,
        bool _canOverFluctuationLimit
    ) internal view {
        // Skip the check if the limit is 0
        if (fluctuationLimitRatio == 0) {
            return;
        }

        //
        // assume the price of the last block is 10, fluctuation limit ratio is 5%, then
        //
        //          current price
        //  --+---------+-----------+---
        //   9.5        10         10.5
        // lower limit           upper limit
        //
        // when `openPosition`, the price can only be between 9.5 - 10.5
        // when `liquidate` and `closePosition`, the price can exceed the boundary once
        // (either lower than 9.5 or higher than 10.5)
        // once it exceeds the boundary, all the rest txs in this block fail
        //

        (uint256 upperLimit, uint256 lowerLimit) = _getPriceBoundariesOfLastBlock();

        uint256 price = _quoteAssetReserve.divD(_baseAssetReserve);
        require(price <= upperLimit && price >= lowerLimit, "AMM_POFL"); //price is already over fluctuation limit

        if (!_canOverFluctuationLimit) {
            price = (_dirOfQuote == Dir.ADD_TO_AMM)
                ? (_quoteAssetReserve + _quoteAssetAmount).divD(_baseAssetReserve - _baseAssetAmount)
                : (_quoteAssetReserve - _quoteAssetAmount).divD(_baseAssetReserve + _baseAssetAmount);
            require(price <= upperLimit && price >= lowerLimit, "AMM_POFL"); //price is over fluctuation limit
        }
    }

    function _implShutdown() internal {
        uint256 _quoteAssetReserve = quoteAssetReserve;
        uint256 _baseAssetReserve = baseAssetReserve;
        int256 _totalPositionSize = getBaseAssetDelta();
        uint256 initBaseReserve = (_totalPositionSize + _baseAssetReserve.toInt()).abs();
        if (initBaseReserve > IGNORABLE_DIGIT_FOR_SHUTDOWN) {
            uint256 initQuoteReserve = Math.mulDiv(_quoteAssetReserve, _baseAssetReserve, initBaseReserve);
            int256 positionNotionalValue = initQuoteReserve.toInt() - _quoteAssetReserve.toInt();
            // if total position size less than IGNORABLE_DIGIT_FOR_SHUTDOWN, treat it as 0 positions due to rounding error
            if (_totalPositionSize.toUint() > IGNORABLE_DIGIT_FOR_SHUTDOWN) {
                settlementPrice = positionNotionalValue.abs().divD(_totalPositionSize.abs());
            }
        }
        open = false;
        emit Shutdown(settlementPrice);
    }

    function _requireRatio(uint256 _ratio) private pure {
        require(_ratio <= 1 ether, "AMM_IR"); //invalid ratio
    }

    function _requireNonZeroAddress(address _input) private pure {
        require(_input != address(0), "AMM_ZA");
    }

    function _requireNonZeroInput(uint256 _input) private pure {
        require(_input != 0, "AMM_ZI"); //zero input
    }
}

