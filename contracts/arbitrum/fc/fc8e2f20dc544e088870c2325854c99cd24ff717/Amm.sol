// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { BlockContext } from "./BlockContext.sol";
import { IPriceFeed } from "./IPriceFeed.sol";
import { SafeMath } from "./SafeMath.sol";
import { IERC20 } from "./IERC20.sol";
import { Decimal } from "./Decimal.sol";
import { SignedDecimal } from "./SignedDecimal.sol";
import { MixedDecimal } from "./MixedDecimal.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IAmm } from "./IAmm.sol";
import { ClearingHouse } from "./ClearingHouse.sol";

contract Amm is IAmm, OwnableUpgradeable, BlockContext {
    using SafeMath for uint256;
    using Decimal for Decimal.decimal;
    using SignedDecimal for SignedDecimal.signedDecimal;
    using MixedDecimal for SignedDecimal.signedDecimal;

    //
    // EVENTS
    //
    event SwapInput(Dir dir, uint256 quoteAssetAmount, uint256 baseAssetAmount);
    event SwapOutput(Dir dir, uint256 quoteAssetAmount, uint256 baseAssetAmount);
    event FundingRateUpdated(int256 rate, uint256 underlyingPrice);
    event ReserveSnapshotted(
        uint256 quoteAssetReserve,
        uint256 baseAssetReserve,
        uint256 timestamp
    );
    event CapChanged(uint256 maxHoldingBaseAsset, uint256 openInterestNotionalCap);
    event PriceFeedUpdated(address priceFeed);
    event Repeg(uint256 quoteAssetReserve, uint256 baseAssetReserve);
    event initMarginRatioChanged(uint256 marginRatio);
    event MaintenanceMarginRatioChanged(uint256 marginRatio);

    //
    // MODIFIERS
    //
    modifier onlyOpen() {
        require(open, "amm was closed");
        _;
    }

    modifier onlyCounterParty() {
        require(counterParty == _msgSender(), "caller is not counterParty");
        _;
    }

    //
    // enum and struct
    //
    struct ReserveSnapshot {
        Decimal.decimal quoteAssetReserve;
        Decimal.decimal baseAssetReserve;
        uint256 timestamp;
        uint256 blockNumber;
    }

    // internal usage
    enum QuoteAssetDir {
        QUOTE_IN,
        QUOTE_OUT
    }
    // internal usage
    enum TwapCalcOption {
        RESERVE_ASSET,
        INPUT_ASSET
    }

    // To record current base/quote asset to calculate TWAP

    struct TwapInputAsset {
        Dir dir;
        Decimal.decimal assetAmount;
        QuoteAssetDir inOrOut;
    }

    struct TwapPriceCalcParams {
        TwapCalcOption opt;
        uint256 snapshotIndex;
        TwapInputAsset asset;
    }

    //
    // Constant
    //
    // 10%
    uint256 public constant MAX_ORACLE_SPREAD_RATIO = 1e17;

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    // DEPRECATED
    // update during every swap and calculate total amm pnl per funding period
    SignedDecimal.signedDecimal private baseAssetDeltaThisFundingPeriod;

    // update during every swap and used when shutting amm down. it's trader's total base asset size
    SignedDecimal.signedDecimal public totalPositionSize;

    // latest funding rate = ((twap market price - twap oracle price) / twap oracle price) / 24
    SignedDecimal.signedDecimal public fundingRate;

    SignedDecimal.signedDecimal private cumulativeNotional;

    Decimal.decimal public tradeLimitRatio;
    Decimal.decimal public quoteAssetReserve;
    Decimal.decimal public baseAssetReserve;
    Decimal.decimal public fluctuationLimitRatio;

    // owner can update
    Decimal.decimal public tollRatio;
    Decimal.decimal public spreadRatio;
    Decimal.decimal public tollAmount;
    Decimal.decimal private maxHoldingBaseAsset;
    Decimal.decimal private openInterestNotionalCap;
    Decimal.decimal public level1DynamicFeeThreshold;
    Decimal.decimal public level2DynamicFeeThreshold;
    Decimal.decimal public level1DynamicFeePercent;
    Decimal.decimal public level2DynamicFeePercent;

    uint256 public spotPriceTwapInterval;
    uint256 public fundingPeriod;
    uint256 public fundingBufferPeriod;
    uint256 public nextFundingTime;
    bytes32 public priceFeedKey;
    ReserveSnapshot[] public reserveSnapshots;

    address private counterParty;
    IERC20 public override quoteAsset;
    IPriceFeed public priceFeed;
    bool public override open;
    uint256[50] private __gap;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//
    Decimal.decimal private _x0;
    Decimal.decimal private _y0;

    Decimal.decimal public level1DynamicFeePercentInFavor;
    Decimal.decimal public level2DynamicFeePercentInFavor;

    Decimal.decimal private _initMarginRatio; // leverage per amm
    Decimal.decimal private _maintenanceMarginRatio;

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//

    //
    // FUNCTIONS
    //
    function initialize(
        uint256 initMarginRatio_,
        uint256 maintenanceMarginRatio_,
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
            initMarginRatio_ != 0 &&
                maintenanceMarginRatio_ != 0 &&
                _quoteAssetReserve != 0 &&
                _tradeLimitRatio != 0 &&
                _baseAssetReserve != 0 &&
                _fundingPeriod != 0 &&
                address(_priceFeed) != address(0) &&
                _quoteAsset != address(0),
            "invalid input"
        );
        __Ownable_init();

        _initMarginRatio = Decimal.decimal(initMarginRatio_);
        _maintenanceMarginRatio = Decimal.decimal(maintenanceMarginRatio_);
        quoteAssetReserve = Decimal.decimal(_quoteAssetReserve);
        baseAssetReserve = Decimal.decimal(_baseAssetReserve);
        tradeLimitRatio = Decimal.decimal(_tradeLimitRatio);
        tollRatio = Decimal.decimal(_tollRatio);
        spreadRatio = Decimal.decimal(_spreadRatio);
        fluctuationLimitRatio = Decimal.decimal(_fluctuationLimitRatio);
        fundingPeriod = _fundingPeriod;
        fundingBufferPeriod = _fundingPeriod.div(2);
        spotPriceTwapInterval = 1 hours;
        priceFeedKey = _priceFeedKey;
        quoteAsset = IERC20(_quoteAsset);
        priceFeed = _priceFeed;
        reserveSnapshots.push(
            ReserveSnapshot(quoteAssetReserve, baseAssetReserve, _blockTimestamp(), _blockNumber())
        );
        emit ReserveSnapshotted(
            quoteAssetReserve.toUint(),
            baseAssetReserve.toUint(),
            _blockTimestamp()
        );
        _x0 = Decimal.decimal(_baseAssetReserve);
        _y0 = Decimal.decimal(_quoteAssetReserve);
    }

    /**
     * @notice Swap your quote asset to base asset, the impact of the price MUST be less than `fluctuationLimitRatio`
     * @dev Only clearingHouse can call this function
     * @param _dirOfQuote ADD_TO_AMM for long, REMOVE_FROM_AMM for short
     * @param _quoteAssetAmount quote asset amount
     * @param _baseAssetAmountLimit minimum base asset amount expected to get to prevent front running
     * @param _canOverFluctuationLimit if tx can go over fluctuation limit once; for partial liquidation
     * @return base asset amount
     */
    function swapInput(
        Dir _dirOfQuote,
        Decimal.decimal calldata _quoteAssetAmount,
        Decimal.decimal calldata _baseAssetAmountLimit,
        bool _canOverFluctuationLimit
    ) external override onlyOpen onlyCounterParty returns (Decimal.decimal memory) {
        if (_quoteAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }
        if (_dirOfQuote == Dir.REMOVE_FROM_AMM) {
            require(
                quoteAssetReserve.mulD(tradeLimitRatio).toUint() >= _quoteAssetAmount.toUint(),
                "over trading limit"
            );
        }

        Decimal.decimal memory baseAssetAmount = getInputPrice(_dirOfQuote, _quoteAssetAmount);
        // If LONG, exchanged base amount should be more than _baseAssetAmountLimit,
        // otherwise(SHORT), exchanged base amount should be less than _baseAssetAmountLimit.
        // In SHORT case, more position means more debt so should not be larger than _baseAssetAmountLimit
        if (_baseAssetAmountLimit.toUint() != 0) {
            if (_dirOfQuote == Dir.ADD_TO_AMM) {
                require(
                    baseAssetAmount.toUint() >= _baseAssetAmountLimit.toUint(),
                    "Less than minimal base token"
                );
            } else {
                require(
                    baseAssetAmount.toUint() <= _baseAssetAmountLimit.toUint(),
                    "More than maximal base token"
                );
            }
        }

        updateReserve(_dirOfQuote, _quoteAssetAmount, baseAssetAmount, _canOverFluctuationLimit);
        emit SwapInput(_dirOfQuote, _quoteAssetAmount.toUint(), baseAssetAmount.toUint());
        return baseAssetAmount;
    }

    /**
     * @notice swap your base asset to quote asset; NOTE it is only used during close/liquidate positions so it always allows going over fluctuation limit
     * @dev only clearingHouse can call this function
     * @param _dirOfBase ADD_TO_AMM for short, REMOVE_FROM_AMM for long, opposite direction from swapInput
     * @param _baseAssetAmount base asset amount
     * @param _quoteAssetAmountLimit limit of quote asset amount; for slippage protection
     * @return quote asset amount
     */
    function swapOutput(
        Dir _dirOfBase,
        Decimal.decimal calldata _baseAssetAmount,
        Decimal.decimal calldata _quoteAssetAmountLimit
    ) external override onlyOpen onlyCounterParty returns (Decimal.decimal memory) {
        return implSwapOutput(_dirOfBase, _baseAssetAmount, _quoteAssetAmountLimit);
    }

    /**
     * @notice update funding rate
     * @dev only allow to update while reaching `nextFundingTime`
     * @return premium fraction of this period in 18 digits
     */
    function settleFunding()
        external
        override
        onlyOpen
        onlyCounterParty
        returns (SignedDecimal.signedDecimal memory)
    {
        require(_blockTimestamp() >= nextFundingTime, "settle funding too early");

        // premium = twapMarketPrice - twapIndexPrice
        // timeFraction = fundingPeriod(1 hour) / 1 day
        // premiumFraction = premium * timeFraction
        Decimal.decimal memory underlyingPrice = getUnderlyingTwapPrice(spotPriceTwapInterval);
        SignedDecimal.signedDecimal memory premium = MixedDecimal
            .fromDecimal(getTwapPrice(spotPriceTwapInterval))
            .subD(underlyingPrice);
        SignedDecimal.signedDecimal memory premiumFraction = premium
            .mulScalar(fundingPeriod)
            .divScalar(int256(1 days));

        // update funding rate = premiumFraction / twapIndexPrice
        updateFundingRate(premiumFraction, underlyingPrice);

        // in order to prevent multiple funding settlement during very short time after network congestion
        uint256 minNextValidFundingTime = _blockTimestamp().add(fundingBufferPeriod);

        // floor((nextFundingTime + fundingPeriod) / 3600) * 3600
        uint256 nextFundingTimeOnHourStart = nextFundingTime.add(fundingPeriod).div(1 hours).mul(
            1 hours
        );

        // max(nextFundingTimeOnHourStart, minNextValidFundingTime)
        nextFundingTime = nextFundingTimeOnHourStart > minNextValidFundingTime
            ? nextFundingTimeOnHourStart
            : minNextValidFundingTime;

        // DEPRECATED only for backward compatibility before we upgrade ClearingHouse
        // reset funding related states
        baseAssetDeltaThisFundingPeriod = SignedDecimal.zero();

        return premiumFraction;
    }

    /**
     * Set K (Repeg both reserves)
     * - Only repeg bot
     */
    function repeg(
        Decimal.decimal memory _quoteAssetReserve,
        Decimal.decimal memory _baseAssetReserve
    ) public onlyCounterParty {
        require(_quoteAssetReserve.toUint() != 0, "quote asset reserve cannot be 0");
        require(_baseAssetReserve.toUint() != 0, "quote asset reserve cannot be 0");
        quoteAssetReserve = _quoteAssetReserve;
        baseAssetReserve = _baseAssetReserve;
        _x0 = _baseAssetReserve;
        _y0 = _quoteAssetReserve;
        addReserveSnapshot();
        emit Repeg(quoteAssetReserve.toUint(), baseAssetReserve.toUint());
    }

    /**
     * @notice set counter party
     * @dev only owner can call this function
     * @param _counterParty address of counter party
     */
    function setCounterParty(address _counterParty) external onlyOwner {
        counterParty = _counterParty;
    }

    /**
     * @notice set fluctuation limit rate. Default value is `1 / max leverage`
     * @dev only owner can call this function
     * @param _fluctuationLimitRatio fluctuation limit rate in 18 digits, 0 means skip the checking
     */
    function setFluctuationLimitRatio(Decimal.decimal memory _fluctuationLimitRatio)
        public
        onlyOwner
    {
        fluctuationLimitRatio = _fluctuationLimitRatio;
    }

    /**
     * Set level 1 dynamic fee settings
     * only owner
     */
    function setLevel1DynamicFeeSettings(
        Decimal.decimal memory _level1DynamicFeeThreshold,
        Decimal.decimal memory _level1DynamicFeePercent,
        Decimal.decimal memory _level1DynamicFeePercentInFavor
    ) public onlyOwner {
        level1DynamicFeeThreshold = _level1DynamicFeeThreshold;
        level1DynamicFeePercent = _level1DynamicFeePercent;
        level1DynamicFeePercentInFavor = _level1DynamicFeePercentInFavor;
    }

    /**
     * Set level 2 dynamic fee settings
     * only owner
     */
    function setLevel2DynamicFeeSettings(
        Decimal.decimal memory _level2DynamicFeeThreshold,
        Decimal.decimal memory _level2DynamicFeePercent,
        Decimal.decimal memory _level2DynamicFeePercentInFavor
    ) public onlyOwner {
        level2DynamicFeeThreshold = _level2DynamicFeeThreshold;
        level2DynamicFeePercent = _level2DynamicFeePercent;
        level2DynamicFeePercentInFavor = _level2DynamicFeePercentInFavor;
    }

    /**
     * @notice set time interval for twap calculation, default is 1 hour
     * @dev only owner can call this function
     * @param _interval time interval in seconds
     */
    function setSpotPriceTwapInterval(uint256 _interval) external onlyOwner {
        require(_interval != 0, "can not set interval to 0");
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
            nextFundingTime = _blockTimestamp().add(fundingPeriod).div(1 hours).mul(1 hours);
        }
    }

    /**
     * @notice set new toll ratio
     * @dev only owner can call
     * @param _tollRatio new toll ratio in 18 digits
     */
    function setTollRatio(Decimal.decimal memory _tollRatio) public onlyOwner {
        tollRatio = _tollRatio;
    }

    /**
     * @notice set new spread ratio
     * @dev only owner can call
     * @param _spreadRatio new toll spread in 18 digits
     */
    function setSpreadRatio(Decimal.decimal memory _spreadRatio) public onlyOwner {
        spreadRatio = _spreadRatio;
    }

    /**
     * @notice set new cap during guarded period, which is max position size that traders can hold
     * @dev only owner can call. assume this will be removes soon once the guarded period has ended. must be set before opening amm
     * @param _maxHoldingBaseAsset max position size that traders can hold in 18 digits
     * @param _openInterestNotionalCap open interest cap, denominated in quoteToken
     */
    function setCap(
        Decimal.decimal memory _maxHoldingBaseAsset,
        Decimal.decimal memory _openInterestNotionalCap
    ) public onlyOwner {
        maxHoldingBaseAsset = _maxHoldingBaseAsset;
        openInterestNotionalCap = _openInterestNotionalCap;
        emit CapChanged(maxHoldingBaseAsset.toUint(), openInterestNotionalCap.toUint());
    }

    /**
     * @notice set priceFee address
     * @dev only owner can call
     * @param _priceFeed new price feed for this AMM
     */
    function setPriceFeed(IPriceFeed _priceFeed) public onlyOwner {
        require(address(_priceFeed) != address(0), "invalid PriceFeed address");
        priceFeed = _priceFeed;
        emit PriceFeedUpdated(address(priceFeed));
    }

    //
    // VIEW FUNCTIONS
    //

    function isOverFluctuationLimit(Dir _dirOfBase, Decimal.decimal memory _baseAssetAmount)
        external
        view
        override
        returns (bool)
    {
        // Skip the check if the limit is 0
        if (fluctuationLimitRatio.toUint() == 0) {
            return false;
        }

        (
            Decimal.decimal memory upperLimit,
            Decimal.decimal memory lowerLimit
        ) = getPriceBoundariesOfLastBlock();

        Decimal.decimal memory quoteAssetExchanged = getOutputPrice(_dirOfBase, _baseAssetAmount);
        Decimal.decimal memory price = (_dirOfBase == Dir.REMOVE_FROM_AMM)
            ? quoteAssetReserve.addD(quoteAssetExchanged).divD(
                baseAssetReserve.subD(_baseAssetAmount)
            )
            : quoteAssetReserve.subD(quoteAssetExchanged).divD(
                baseAssetReserve.addD(_baseAssetAmount)
            );

        if (price.cmp(upperLimit) <= 0 && price.cmp(lowerLimit) >= 0) {
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
    function getInputTwap(Dir _dirOfQuote, Decimal.decimal memory _quoteAssetAmount)
        public
        view
        override
        returns (Decimal.decimal memory)
    {
        return
            implGetInputAssetTwapPrice(
                _dirOfQuote,
                _quoteAssetAmount,
                QuoteAssetDir.QUOTE_IN,
                15 minutes
            );
    }

    /**
     * @notice get output twap amount.
     * return how many quote asset you will get with the input base amount on twap price.
     * @param _dirOfBase ADD_TO_AMM for short, REMOVE_FROM_AMM for long, opposite direction from `getInputTwap`.
     * @param _baseAssetAmount base asset amount
     * @return quote asset amount
     */
    function getOutputTwap(Dir _dirOfBase, Decimal.decimal memory _baseAssetAmount)
        public
        view
        override
        returns (Decimal.decimal memory)
    {
        return
            implGetInputAssetTwapPrice(
                _dirOfBase,
                _baseAssetAmount,
                QuoteAssetDir.QUOTE_OUT,
                15 minutes
            );
    }

    /**
     * @notice get input amount. returns how many base asset you will get with the input quote amount.
     * @param _dirOfQuote ADD_TO_AMM for long, REMOVE_FROM_AMM for short.
     * @param _quoteAssetAmount quote asset amount
     * @return base asset amount
     */
    function getInputPrice(Dir _dirOfQuote, Decimal.decimal memory _quoteAssetAmount)
        public
        view
        override
        returns (Decimal.decimal memory)
    {
        return
            getInputPriceWithReserves(
                _dirOfQuote,
                _quoteAssetAmount,
                quoteAssetReserve,
                baseAssetReserve
            );
    }

    /**
     * @notice get output price. return how many quote asset you will get with the input base amount
     * @param _dirOfBase ADD_TO_AMM for short, REMOVE_FROM_AMM for long, opposite direction from `getInput`.
     * @param _baseAssetAmount base asset amount
     * @return quote asset amount
     */
    function getOutputPrice(Dir _dirOfBase, Decimal.decimal memory _baseAssetAmount)
        public
        view
        override
        returns (Decimal.decimal memory)
    {
        return
            getOutputPriceWithReserves(
                _dirOfBase,
                _baseAssetAmount,
                quoteAssetReserve,
                baseAssetReserve
            );
    }

    /**
     * @notice get underlying price provided by oracle
     * @return underlying price
     */
    function getUnderlyingPrice() public view override returns (Decimal.decimal memory) {
        return Decimal.decimal(priceFeed.getPrice(priceFeedKey));
    }

    /**
     * @notice get underlying twap price provided by oracle
     * @return underlying price
     */
    function getUnderlyingTwapPrice(uint256 _intervalInSeconds)
        public
        view
        returns (Decimal.decimal memory)
    {
        return Decimal.decimal(priceFeed.getTwapPrice(priceFeedKey, _intervalInSeconds));
    }

    /**
     * @notice get spot price based on current quote/base asset reserve.
     * @return spot price
     */
    function getSpotPrice() public view override returns (Decimal.decimal memory) {
        return quoteAssetReserve.divD(baseAssetReserve);
    }

    /**
     * @notice get twap price
     */
    function getTwapPrice(uint256 _intervalInSeconds) public view returns (Decimal.decimal memory) {
        return implGetReserveTwapPrice(_intervalInSeconds);
    }

    /**
     * @notice get current quote/base asset reserve.
     * @return (quote asset reserve, base asset reserve)
     */
    function getReserve() external view returns (Decimal.decimal memory, Decimal.decimal memory) {
        return (quoteAssetReserve, baseAssetReserve);
    }

    function getSnapshotLen() external view returns (uint256) {
        return reserveSnapshots.length;
    }

    function getCumulativeNotional()
        external
        view
        override
        returns (SignedDecimal.signedDecimal memory)
    {
        return cumulativeNotional;
    }

    // DEPRECATED only for backward compatibility before we upgrade ClearingHouse
    function getBaseAssetDeltaThisFundingPeriod()
        external
        view
        override
        returns (SignedDecimal.signedDecimal memory)
    {
        return baseAssetDeltaThisFundingPeriod;
    }

    function getMaxHoldingBaseAsset() external view override returns (Decimal.decimal memory) {
        return maxHoldingBaseAsset;
    }

    function getOpenInterestNotionalCap() external view override returns (Decimal.decimal memory) {
        return openInterestNotionalCap;
    }

    function getBaseAssetDelta()
        external
        view
        override
        returns (SignedDecimal.signedDecimal memory)
    {
        return totalPositionSize;
    }

    function isOverSpreadLimit() external view override returns (bool) {
        Decimal.decimal memory oraclePrice = getUnderlyingPrice();
        require(oraclePrice.toUint() > 0, "underlying price is 0");
        Decimal.decimal memory marketPrice = getSpotPrice();
        Decimal.decimal memory oracleSpreadRatioAbs = MixedDecimal
            .fromDecimal(marketPrice)
            .subD(oraclePrice)
            .divD(oraclePrice)
            .abs();

        return oracleSpreadRatioAbs.toUint() >= MAX_ORACLE_SPREAD_RATIO ? true : false;
    }

    /**
     * @notice calculate total fee (including toll and spread) by input quoteAssetAmount
     * @param _quoteAssetAmount quoteAssetAmount
     * @return total tx fee
     */
    function calcFee(Decimal.decimal calldata _quoteAssetAmount, ClearingHouse.Side _side)
        external
        view
        override
        returns (Decimal.decimal memory, Decimal.decimal memory)
    {
        if (_quoteAssetAmount.toUint() == 0) {
            return (Decimal.zero(), Decimal.zero());
        }
        Decimal.decimal memory spread = spreadRatio;
        Decimal.decimal memory toll = tollRatio;
        Decimal.decimal memory fee;
        Decimal.decimal memory markPrice = getSpotPrice();
        Decimal.decimal memory indexPrice = getUnderlyingPrice();
        Decimal.decimal memory divergence = MixedDecimal
            .fromDecimal(indexPrice)
            .subD(markPrice)
            .abs();

        // dynamic fees
        Decimal.decimal memory level2Amount = markPrice.mulD(level2DynamicFeeThreshold);
        Decimal.decimal memory level1Amount = markPrice.mulD(level1DynamicFeeThreshold);
        bool isInFavor = (
            markPrice.toUint() > indexPrice.toUint()
                ? ClearingHouse.Side.SELL
                : ClearingHouse.Side.BUY
        ) == _side;

        if (level2Amount.toUint() != 0 && divergence.toUint() > level2Amount.toUint()) {
            if (isInFavor) {
                fee = level2DynamicFeePercentInFavor.divScalar(2);
            } else {
                require(level2DynamicFeePercent.toUint() != 0, "level 2 d fees not set");
                fee = level2DynamicFeePercent.divScalar(2);
            }
            spread = fee;
            toll = fee;
        } else if (level1Amount.toUint() != 0 && divergence.toUint() > level1Amount.toUint()) {
            if (isInFavor) {
                fee = level1DynamicFeePercentInFavor.divScalar(2);
            } else {
                require(level1DynamicFeePercent.toUint() != 0, "level 1 d fees not set");
                fee = level1DynamicFeePercent.divScalar(2);
            }
            spread = fee;
            toll = fee;
        }
        return (_quoteAssetAmount.mulD(toll), _quoteAssetAmount.mulD(spread));
    }

    /*       plus/minus 1 while the amount is not dividable
     *
     *        getInputPrice                         getOutputPrice
     *
     *     ＡＤＤ      (amount - 1)              (amount + 1)   ＲＥＭＯＶＥ
     *      ◥◤            ▲                         |             ◢◣
     *      ◥◤  ------->  |                         ▼  <--------  ◢◣
     *    -------      -------                   -------        -------
     *    |  Q  |      |  B  |                   |  Q  |        |  B  |
     *    -------      -------                   -------        -------
     *      ◥◤  ------->  ▲                         |  <--------  ◢◣
     *      ◥◤            |                         ▼             ◢◣
     *   ＲＥＭＯＶＥ  (amount + 1)              (amount + 1)      ＡＤＤ
     **/

    function getInputPriceWithReserves(
        Dir _dirOfQuote,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) public pure override returns (Decimal.decimal memory) {
        if (_quoteAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }

        bool isAddToAmm = _dirOfQuote == Dir.ADD_TO_AMM;
        SignedDecimal.signedDecimal memory invariant = MixedDecimal.fromDecimal(
            _quoteAssetPoolAmount.mulD(_baseAssetPoolAmount)
        );
        SignedDecimal.signedDecimal memory baseAssetAfter;
        Decimal.decimal memory quoteAssetAfter;
        Decimal.decimal memory baseAssetBought;
        if (isAddToAmm) {
            quoteAssetAfter = _quoteAssetPoolAmount.addD(_quoteAssetAmount);
        } else {
            quoteAssetAfter = _quoteAssetPoolAmount.subD(_quoteAssetAmount);
        }
        require(quoteAssetAfter.toUint() != 0, "quote asset after is 0");

        baseAssetAfter = invariant.divD(quoteAssetAfter);
        baseAssetBought = baseAssetAfter.subD(_baseAssetPoolAmount).abs();

        // if the amount is not dividable, return 1 wei less for trader
        if (invariant.abs().modD(quoteAssetAfter).toUint() != 0) {
            if (isAddToAmm) {
                baseAssetBought = baseAssetBought.subD(Decimal.decimal(1));
            } else {
                baseAssetBought = baseAssetBought.addD(Decimal.decimal(1));
            }
        }

        return baseAssetBought;
    }

    function getOutputPriceWithReserves(
        Dir _dirOfBase,
        Decimal.decimal memory _baseAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) public pure override returns (Decimal.decimal memory) {
        if (_baseAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }

        bool isAddToAmm = _dirOfBase == Dir.ADD_TO_AMM;
        SignedDecimal.signedDecimal memory invariant = MixedDecimal.fromDecimal(
            _quoteAssetPoolAmount.mulD(_baseAssetPoolAmount)
        );
        SignedDecimal.signedDecimal memory quoteAssetAfter;
        Decimal.decimal memory baseAssetAfter;
        Decimal.decimal memory quoteAssetSold;

        if (isAddToAmm) {
            baseAssetAfter = _baseAssetPoolAmount.addD(_baseAssetAmount);
        } else {
            baseAssetAfter = _baseAssetPoolAmount.subD(_baseAssetAmount);
        }
        require(baseAssetAfter.toUint() != 0, "base asset after is 0");

        quoteAssetAfter = invariant.divD(baseAssetAfter);
        quoteAssetSold = quoteAssetAfter.subD(_quoteAssetPoolAmount).abs();

        // if the amount is not dividable, return 1 wei less for trader
        if (invariant.abs().modD(baseAssetAfter).toUint() != 0) {
            if (isAddToAmm) {
                quoteAssetSold = quoteAssetSold.subD(Decimal.decimal(1));
            } else {
                quoteAssetSold = quoteAssetSold.addD(Decimal.decimal(1));
            }
        }

        return quoteAssetSold;
    }

    //
    // INTERNAL FUNCTIONS
    //
    // update funding rate = premiumFraction / twapIndexPrice
    function updateFundingRate(
        SignedDecimal.signedDecimal memory _premiumFraction,
        Decimal.decimal memory _underlyingPrice
    ) private {
        fundingRate = _premiumFraction.divD(_underlyingPrice);
        emit FundingRateUpdated(fundingRate.toInt(), _underlyingPrice.toUint());
    }

    function addReserveSnapshot() internal {
        uint256 currentBlock = _blockNumber();
        ReserveSnapshot storage latestSnapshot = reserveSnapshots[reserveSnapshots.length - 1];
        // update values in snapshot if in the same block
        if (currentBlock == latestSnapshot.blockNumber) {
            latestSnapshot.quoteAssetReserve = quoteAssetReserve;
            latestSnapshot.baseAssetReserve = baseAssetReserve;
        } else {
            reserveSnapshots.push(
                ReserveSnapshot(
                    quoteAssetReserve,
                    baseAssetReserve,
                    _blockTimestamp(),
                    currentBlock
                )
            );
        }
        emit ReserveSnapshotted(
            quoteAssetReserve.toUint(),
            baseAssetReserve.toUint(),
            _blockTimestamp()
        );
    }

    function implSwapOutput(
        Dir _dirOfBase,
        Decimal.decimal memory _baseAssetAmount,
        Decimal.decimal memory _quoteAssetAmountLimit
    ) internal returns (Decimal.decimal memory) {
        if (_baseAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }
        if (_dirOfBase == Dir.REMOVE_FROM_AMM) {
            require(
                baseAssetReserve.mulD(tradeLimitRatio).toUint() >= _baseAssetAmount.toUint(),
                "over trading limit"
            );
        }

        Decimal.decimal memory quoteAssetAmount = getOutputPrice(_dirOfBase, _baseAssetAmount);
        Dir dirOfQuote = _dirOfBase == Dir.ADD_TO_AMM ? Dir.REMOVE_FROM_AMM : Dir.ADD_TO_AMM;
        // If SHORT, exchanged quote amount should be less than _quoteAssetAmountLimit,
        // otherwise(LONG), exchanged base amount should be more than _quoteAssetAmountLimit.
        // In the SHORT case, more quote assets means more payment so should not be more than _quoteAssetAmountLimit
        if (_quoteAssetAmountLimit.toUint() != 0) {
            if (dirOfQuote == Dir.REMOVE_FROM_AMM) {
                // SHORT
                require(
                    quoteAssetAmount.toUint() >= _quoteAssetAmountLimit.toUint(),
                    "Less than minimal quote token"
                );
            } else {
                // LONG
                require(
                    quoteAssetAmount.toUint() <= _quoteAssetAmountLimit.toUint(),
                    "More than maximal quote token"
                );
            }
        }

        // as mentioned in swapOutput(), it always allows going over fluctuation limit because
        // it is only used by close/liquidate positions
        updateReserve(dirOfQuote, quoteAssetAmount, _baseAssetAmount, true);
        emit SwapOutput(_dirOfBase, quoteAssetAmount.toUint(), _baseAssetAmount.toUint());
        return quoteAssetAmount;
    }

    // the direction is in quote asset
    function updateReserve(
        Dir _dirOfQuote,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _baseAssetAmount,
        bool _canOverFluctuationLimit
    ) internal {
        // check if it's over fluctuationLimitRatio
        // this check should be before reserves being updated
        checkIsOverBlockFluctuationLimit(
            _dirOfQuote,
            _quoteAssetAmount,
            _baseAssetAmount,
            _canOverFluctuationLimit
        );

        if (_dirOfQuote == Dir.ADD_TO_AMM) {
            quoteAssetReserve = quoteAssetReserve.addD(_quoteAssetAmount);
            baseAssetReserve = baseAssetReserve.subD(_baseAssetAmount);
            // DEPRECATED only for backward compatibility before we upgrade ClearingHouse
            baseAssetDeltaThisFundingPeriod = baseAssetDeltaThisFundingPeriod.subD(
                _baseAssetAmount
            );
            totalPositionSize = totalPositionSize.addD(_baseAssetAmount);
            cumulativeNotional = cumulativeNotional.addD(_quoteAssetAmount);
        } else {
            quoteAssetReserve = quoteAssetReserve.subD(_quoteAssetAmount);
            baseAssetReserve = baseAssetReserve.addD(_baseAssetAmount);
            // DEPRECATED only for backward compatibility before we upgrade ClearingHouse
            baseAssetDeltaThisFundingPeriod = baseAssetDeltaThisFundingPeriod.addD(
                _baseAssetAmount
            );
            totalPositionSize = totalPositionSize.subD(_baseAssetAmount);
            cumulativeNotional = cumulativeNotional.subD(_quoteAssetAmount);
        }

        // addReserveSnapshot must be after checking price fluctuation
        addReserveSnapshot();
    }

    function implGetInputAssetTwapPrice(
        Dir _dirOfQuote,
        Decimal.decimal memory _assetAmount,
        QuoteAssetDir _inOut,
        uint256 _interval
    ) internal view returns (Decimal.decimal memory) {
        TwapPriceCalcParams memory params;
        params.opt = TwapCalcOption.INPUT_ASSET;
        params.snapshotIndex = reserveSnapshots.length.sub(1);
        params.asset.dir = _dirOfQuote;
        params.asset.assetAmount = _assetAmount;
        params.asset.inOrOut = _inOut;
        return calcTwap(params, _interval);
    }

    function implGetReserveTwapPrice(uint256 _interval)
        internal
        view
        returns (Decimal.decimal memory)
    {
        TwapPriceCalcParams memory params;
        params.opt = TwapCalcOption.RESERVE_ASSET;
        params.snapshotIndex = reserveSnapshots.length.sub(1);
        return calcTwap(params, _interval);
    }

    function calcTwap(TwapPriceCalcParams memory _params, uint256 _interval)
        internal
        view
        returns (Decimal.decimal memory)
    {
        Decimal.decimal memory currentPrice = getPriceWithSpecificSnapshot(_params);
        if (_interval == 0) {
            return currentPrice;
        }

        uint256 baseTimestamp = _blockTimestamp().sub(_interval);
        ReserveSnapshot memory currentSnapshot = reserveSnapshots[_params.snapshotIndex];
        // return the latest snapshot price directly
        // if only one snapshot or the timestamp of latest snapshot is earlier than asking for
        if (reserveSnapshots.length == 1 || currentSnapshot.timestamp <= baseTimestamp) {
            return currentPrice;
        }

        uint256 previousTimestamp = currentSnapshot.timestamp;
        uint256 period = _blockTimestamp().sub(previousTimestamp);
        Decimal.decimal memory weightedPrice = currentPrice.mulScalar(period);
        while (true) {
            // if snapshot history is too short
            if (_params.snapshotIndex == 0) {
                return weightedPrice.divScalar(period);
            }

            _params.snapshotIndex = _params.snapshotIndex.sub(1);
            currentSnapshot = reserveSnapshots[_params.snapshotIndex];
            currentPrice = getPriceWithSpecificSnapshot(_params);

            // check if current round timestamp is earlier than target timestamp
            if (currentSnapshot.timestamp <= baseTimestamp) {
                // weighted time period will be (target timestamp - previous timestamp). For example,
                // now is 1000, _interval is 100, then target timestamp is 900. If timestamp of current round is 970,
                // and timestamp of NEXT round is 880, then the weighted time period will be (970 - 900) = 70,
                // instead of (970 - 880)
                weightedPrice = weightedPrice.addD(
                    currentPrice.mulScalar(previousTimestamp.sub(baseTimestamp))
                );
                break;
            }

            uint256 timeFraction = previousTimestamp.sub(currentSnapshot.timestamp);
            weightedPrice = weightedPrice.addD(currentPrice.mulScalar(timeFraction));
            period = period.add(timeFraction);
            previousTimestamp = currentSnapshot.timestamp;
        }
        return weightedPrice.divScalar(_interval);
    }

    function getPriceWithSpecificSnapshot(TwapPriceCalcParams memory params)
        internal
        view
        virtual
        returns (Decimal.decimal memory)
    {
        ReserveSnapshot memory snapshot = reserveSnapshots[params.snapshotIndex];

        // RESERVE_ASSET means price comes from quoteAssetReserve/baseAssetReserve
        // INPUT_ASSET means getInput/Output price with snapshot's reserve
        if (params.opt == TwapCalcOption.RESERVE_ASSET) {
            return snapshot.quoteAssetReserve.divD(snapshot.baseAssetReserve);
        } else if (params.opt == TwapCalcOption.INPUT_ASSET) {
            if (params.asset.assetAmount.toUint() == 0) {
                return Decimal.zero();
            }
            if (params.asset.inOrOut == QuoteAssetDir.QUOTE_IN) {
                return
                    getInputPriceWithReserves(
                        params.asset.dir,
                        params.asset.assetAmount,
                        snapshot.quoteAssetReserve,
                        snapshot.baseAssetReserve
                    );
            } else if (params.asset.inOrOut == QuoteAssetDir.QUOTE_OUT) {
                return
                    getOutputPriceWithReserves(
                        params.asset.dir,
                        params.asset.assetAmount,
                        snapshot.quoteAssetReserve,
                        snapshot.baseAssetReserve
                    );
            }
        }
        revert("not supported option");
    }

    function getPriceBoundariesOfLastBlock()
        internal
        view
        returns (Decimal.decimal memory, Decimal.decimal memory)
    {
        uint256 len = reserveSnapshots.length;
        ReserveSnapshot memory latestSnapshot = reserveSnapshots[len.sub(1)];
        // if the latest snapshot is the same as current block, get the previous one
        if (latestSnapshot.blockNumber == _blockNumber() && len > 1) {
            latestSnapshot = reserveSnapshots[len.sub(2)];
        }

        Decimal.decimal memory lastPrice = latestSnapshot.quoteAssetReserve.divD(
            latestSnapshot.baseAssetReserve
        );
        Decimal.decimal memory upperLimit = lastPrice.mulD(
            Decimal.one().addD(fluctuationLimitRatio)
        );
        Decimal.decimal memory lowerLimit = lastPrice.mulD(
            Decimal.one().subD(fluctuationLimitRatio)
        );
        return (upperLimit, lowerLimit);
    }

    /**
     * @notice there can only be one tx in a block can skip the fluctuation check
     *         otherwise, some positions can never be closed or liquidated
     * @param _canOverFluctuationLimit if true, can skip fluctuation check for once; else, can never skip
     */
    function checkIsOverBlockFluctuationLimit(
        Dir _dirOfQuote,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _baseAssetAmount,
        bool _canOverFluctuationLimit
    ) internal view {
        // Skip the check if the limit is 0
        if (fluctuationLimitRatio.toUint() == 0) {
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

        (
            Decimal.decimal memory upperLimit,
            Decimal.decimal memory lowerLimit
        ) = getPriceBoundariesOfLastBlock();

        Decimal.decimal memory price = quoteAssetReserve.divD(baseAssetReserve);
        require(
            price.cmp(upperLimit) <= 0 && price.cmp(lowerLimit) >= 0,
            "price is already over fluctuation limit"
        );

        if (!_canOverFluctuationLimit) {
            price = (_dirOfQuote == Dir.ADD_TO_AMM)
                ? quoteAssetReserve.addD(_quoteAssetAmount).divD(
                    baseAssetReserve.subD(_baseAssetAmount)
                )
                : quoteAssetReserve.subD(_quoteAssetAmount).divD(
                    baseAssetReserve.addD(_baseAssetAmount)
                );
            require(
                price.cmp(upperLimit) <= 0 && price.cmp(lowerLimit) >= 0,
                "price is over fluctuation limit"
            );
        }
    }

    function x0() external view override returns (Decimal.decimal memory) {
        return _x0;
    }

    function y0() external view override returns (Decimal.decimal memory) {
        return _y0;
    }

    /**
     * @notice set maintenance margin ratio
     * @dev only owner can call
     * @param maintenanceMarginRatio_ new maintenance margin ratio in 18 digits
     */
    function setMaintenanceMarginRatio(Decimal.decimal memory maintenanceMarginRatio_)
        external
        onlyOwner
    {
        _maintenanceMarginRatio = maintenanceMarginRatio_;
        emit MaintenanceMarginRatioChanged(_maintenanceMarginRatio.toUint());
    }

    /**
     * @notice set init margin ratio
     * @dev only owner can call
     * @param initMarginRatio_ new maintenance margin ratio in 18 digits
     */
    function setInitMarginRatio(Decimal.decimal memory initMarginRatio_) external onlyOwner {
        _initMarginRatio = initMarginRatio_;
        emit initMarginRatioChanged(_initMarginRatio.toUint());
    }

    function getInitMarginRatio() external view returns (Decimal.decimal memory) {
        return _initMarginRatio;
    }

    function getMaintenanceMarginRatio() external view returns (Decimal.decimal memory) {
        return _maintenanceMarginRatio;
    }
}

