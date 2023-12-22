// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { IPriceFeed } from "./IPriceFeed.sol";
import { IERC20 } from "./IERC20.sol";
import { Decimal } from "./Decimal.sol";
import { SignedDecimal } from "./SignedDecimal.sol";
import { MixedDecimal } from "./MixedDecimal.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IAmm } from "./IAmm.sol";

// solhint-disable-next-line max-states-count
contract Amm is IAmm, OwnableUpgradeable {
    using Decimal for Decimal.decimal;
    using SignedDecimal for SignedDecimal.signedDecimal;
    using MixedDecimal for SignedDecimal.signedDecimal;

    enum QuoteAssetDir {
        QUOTE_IN,
        QUOTE_OUT
    }

    enum TwapCalcOption {
        RESERVE_ASSET,
        INPUT_ASSET
    }

    struct ReserveSnapshot {
        Decimal.decimal quoteAssetReserve;
        Decimal.decimal baseAssetReserve;
        uint256 timestamp;
        uint256 blockNumber;
    }

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

    struct DynamicFeeSettings {
        Decimal.decimal divergenceThresholdRatio;
        Decimal.decimal feeRatio;
        Decimal.decimal feeInFavorRatio;
    }

    struct FundingRate {
        SignedDecimal.signedDecimal fundingRateLong;
        SignedDecimal.signedDecimal fundingRateShort;
    }

    /**
     * below state variables cannot change their order
     */

    // ratios
    Decimal.decimal internal feeRatio;
    Decimal.decimal public tradeLimitRatio;
    Decimal.decimal public fluctuationLimitRatio;
    Decimal.decimal internal initMarginRatio;
    Decimal.decimal internal maintenanceMarginRatio;
    Decimal.decimal internal partialLiquidationRatio;
    Decimal.decimal internal liquidationFeeRatio;

    // dynamic fees
    DynamicFeeSettings public level1DynamicFeeSettings;
    DynamicFeeSettings public level2DynamicFeeSettings;

    // funding rate
    FundingRate public fundingRate;

    // x and y
    Decimal.decimal public quoteAssetReserve;
    Decimal.decimal public baseAssetReserve;
    Decimal.decimal public k;

    // caps
    Decimal.decimal internal maxHoldingBaseAsset;
    Decimal.decimal internal openInterestNotionalCap;

    SignedDecimal.signedDecimal public totalPositionSize;
    SignedDecimal.signedDecimal public cumulativeNotional;
    SignedDecimal.signedDecimal public baseAssetDeltaThisFundingPeriod;
    Decimal.decimal public _x0;
    Decimal.decimal public _y0;

    uint256 public override fundingPeriod;
    uint256 public markPriceTwapInterval;
    uint256 public nextFundingTime;
    uint256 public fundingBufferPeriod;
    uint256 public lastRepegTimestamp;
    uint256 public repegBufferPeriod;
    IPriceFeed public priceFeed;
    bytes32 public priceFeedKey;
    address public counterParty;
    IERC20 public override quoteAsset;
    bool public override open;

    ReserveSnapshot[] public reserveSnapshots;

    // events
    event Open(bool indexed open);
    event SwapInput(Dir dir, uint256 quoteAssetAmount, uint256 baseAssetAmount);
    event SwapOutput(Dir dir, uint256 quoteAssetAmount, uint256 baseAssetAmount);
    event FundingRateUpdated(
        int256 fundingRateLong,
        int256 fundingRateShort,
        uint256 underlyingPrice
    );
    event ReserveSnapshotted(
        uint256 quoteAssetReserve,
        uint256 baseAssetReserve,
        uint256 timestamp
    );
    event FeeRatioChanged(uint256 ratio);
    event TradeLimitRatioChanged(uint256 ratio);
    event FluctuationLimitRatioChanged(uint256 ratio);
    event InitMarginRatioChanged(uint256 ratio);
    event MaintenanceMarginRatioChanged(uint256 ratio);
    event PartialLiquidationRatioChanged(uint256 ratio);
    event LiquidationFeeRatioChanged(uint256 ratio);
    event FundingPeriodChanged(uint256 fundingPeriod);
    event CapChanged(uint256 maxHoldingBaseAsset, uint256 openInterestNotionalCap);
    event PriceFeedUpdated(address indexed priceFeed);
    event Repeg(
        uint256 quoteAssetReserveBefore,
        uint256 baseAssetReserveBefore,
        uint256 quoteAssetReserveAfter,
        uint256 baseAssetReserveAfter,
        int256 repegPnl
    );

    modifier onlyOpen() {
        require(open, "amm was closed");
        _;
    }

    modifier onlyCounterParty() {
        require(counterParty == _msgSender(), "caller is not counterParty");
        _;
    }

    //
    // EXTERNAL
    //

    /**
     * upgradeable constructor, can only be inited once
     */
    function initialize(
        uint256 _quoteAssetReserve,
        uint256 _baseAssetReserve,
        uint256 _tradeLimitRatio,
        uint256 _fundingPeriod,
        IPriceFeed _priceFeed,
        bytes32 _priceFeedKey,
        address _quoteAsset,
        uint256 _fluctuationLimitRatio,
        uint256 _feeRatio
    ) public initializer {
        require(
            _quoteAssetReserve != 0 &&
                _tradeLimitRatio != 0 &&
                _baseAssetReserve != 0 &&
                _fundingPeriod != 0 &&
                address(_priceFeed) != address(0) &&
                _quoteAsset != address(0),
            "invalid input"
        );
        __Ownable_init();

        quoteAssetReserve = Decimal.decimal(_quoteAssetReserve);
        baseAssetReserve = Decimal.decimal(_baseAssetReserve);
        k = quoteAssetReserve.mulD(baseAssetReserve);
        tradeLimitRatio = Decimal.decimal(_tradeLimitRatio);
        feeRatio = Decimal.decimal(_feeRatio);
        fluctuationLimitRatio = Decimal.decimal(_fluctuationLimitRatio);
        fundingPeriod = _fundingPeriod;
        fundingBufferPeriod = _fundingPeriod / 2;
        repegBufferPeriod = 12 hours;
        markPriceTwapInterval = fundingPeriod;
        priceFeedKey = _priceFeedKey;
        quoteAsset = IERC20(_quoteAsset);
        priceFeed = _priceFeed;
        reserveSnapshots.push(
            ReserveSnapshot(quoteAssetReserve, baseAssetReserve, block.timestamp, block.number)
        );
        emit ReserveSnapshotted(
            quoteAssetReserve.toUint(),
            baseAssetReserve.toUint(),
            block.timestamp
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

        _updateReserve(_dirOfQuote, _quoteAssetAmount, baseAssetAmount, _canOverFluctuationLimit);
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
     * @return premiumFraction of this period in 18 digits
     * @return markPrice of this period in 18 digits
     * @return indexPrice of this period in 18 digits
     */
    function settleFunding()
        external
        override
        onlyOpen
        onlyCounterParty
        returns (
            SignedDecimal.signedDecimal memory premiumFraction,
            Decimal.decimal memory markPrice,
            Decimal.decimal memory indexPrice
        )
    {
        require(block.timestamp >= nextFundingTime, "settle funding too early");

        // premium = twapMarketPrice - twapIndexPrice
        // timeFraction = fundingPeriod(1 hour) / 1 day
        // premiumFraction = premium * timeFraction
        markPrice = getTwapPrice(markPriceTwapInterval);
        indexPrice = getIndexPrice();

        SignedDecimal.signedDecimal memory premium = MixedDecimal.fromDecimal(markPrice).subD(
            indexPrice
        );

        premiumFraction = premium.mulScalar(fundingPeriod).divScalar(int256(1 days));

        // in order to prevent multiple funding settlement during very short time after network congestion
        uint256 minNextValidFundingTime = block.timestamp + fundingBufferPeriod;

        // floor((nextFundingTime + fundingPeriod) / 3600) * 3600
        uint256 nextFundingTimeOnHourStart = ((nextFundingTime + fundingPeriod) / 1 hours) *
            1 hours;

        // max(nextFundingTimeOnHourStart, minNextValidFundingTime)
        nextFundingTime = nextFundingTimeOnHourStart > minNextValidFundingTime
            ? nextFundingTimeOnHourStart
            : minNextValidFundingTime;

        // DEPRECATED only for backward compatibility before we upgrade ClearingHouse
        // reset funding related states
        baseAssetDeltaThisFundingPeriod = SignedDecimal.zero();
    }

    /**
     * @notice repeg mark price to index price
     * @dev only clearing house can call
     */
    function repegPrice()
        external
        override
        onlyOpen
        onlyCounterParty
        returns (
            Decimal.decimal memory,
            Decimal.decimal memory,
            Decimal.decimal memory,
            Decimal.decimal memory,
            SignedDecimal.signedDecimal memory
        )
    {
        require(
            block.timestamp >= lastRepegTimestamp + repegBufferPeriod,
            "repeg interval too small"
        );
        Decimal.decimal memory indexPrice = getIndexPrice();

        // calculation must be done before repeg
        SignedDecimal.signedDecimal memory repegPnl = calcPriceRepegPnl(indexPrice);

        // REPEG, y / x = price, y = price * x
        Decimal.decimal memory quoteAssetReserveBefore = quoteAssetReserve;
        quoteAssetReserve = indexPrice.mulD(baseAssetReserve);
        k = quoteAssetReserve.mulD(baseAssetReserve);
        lastRepegTimestamp = block.timestamp;

        // update repeg checkpoints
        _y0 = quoteAssetReserve;
        _x0 = baseAssetReserve;

        // add reserve snapshot, should be only after updating reserves
        _addReserveSnapshot();

        emit Repeg(
            quoteAssetReserveBefore.toUint(),
            baseAssetReserve.toUint(),
            quoteAssetReserve.toUint(),
            baseAssetReserve.toUint(),
            repegPnl.toInt()
        );
        return (
            quoteAssetReserveBefore,
            baseAssetReserve,
            quoteAssetReserve,
            baseAssetReserve,
            repegPnl
        );
    }

    /**
     * @notice adjust liquidity depth
     * @dev only clearing house can call
     */
    function repegK(Decimal.decimal memory _multiplier)
        external
        override
        onlyOpen
        onlyCounterParty
        returns (
            Decimal.decimal memory,
            Decimal.decimal memory,
            Decimal.decimal memory,
            Decimal.decimal memory,
            SignedDecimal.signedDecimal memory
        )
    {
        require(
            block.timestamp >= lastRepegTimestamp + repegBufferPeriod,
            "repeg interval too small"
        );

        Decimal.decimal memory multiplierSqrt = _multiplier.sqrt();

        Decimal.decimal memory quoteAssetReserveBefore = quoteAssetReserve;
        Decimal.decimal memory baseAssetReserveBefore = baseAssetReserve;

        Decimal.decimal memory quoteAssetReserveAfter = quoteAssetReserveBefore.mulD(
            multiplierSqrt
        );
        Decimal.decimal memory baseAssetReserveAfter = baseAssetReserveBefore.mulD(multiplierSqrt);
        Decimal.decimal memory _k = quoteAssetReserveAfter.mulD(baseAssetReserveAfter);

        // calculation must be done before repeg
        SignedDecimal.signedDecimal memory repegPnl = calcKRepegPnl(_k);

        // REPEG
        quoteAssetReserve = quoteAssetReserveAfter;
        baseAssetReserve = baseAssetReserveAfter;
        k = _k;
        lastRepegTimestamp = block.timestamp;

        // update repeg checkpoints
        _y0 = quoteAssetReserveAfter;
        _x0 = baseAssetReserveAfter;

        // add reserve snapshot, should be only after updating reserves
        _addReserveSnapshot();

        emit Repeg(
            quoteAssetReserveBefore.toUint(),
            baseAssetReserveBefore.toUint(),
            quoteAssetReserveAfter.toUint(),
            baseAssetReserveAfter.toUint(),
            repegPnl.toInt()
        );

        return (
            quoteAssetReserveBefore,
            baseAssetReserveBefore,
            quoteAssetReserveAfter,
            baseAssetReserveAfter,
            repegPnl
        );
    }

    // update funding rate = premiumFraction / twapIndexPrice
    function updateFundingRate(
        SignedDecimal.signedDecimal memory _premiumFractionLong,
        SignedDecimal.signedDecimal memory _premiumFractionShort,
        Decimal.decimal memory _underlyingPrice
    ) external override onlyOpen onlyCounterParty {
        fundingRate.fundingRateLong = _premiumFractionLong.divD(_underlyingPrice);
        fundingRate.fundingRateShort = _premiumFractionShort.divD(_underlyingPrice);
        emit FundingRateUpdated(
            fundingRate.fundingRateLong.toInt(),
            fundingRate.fundingRateShort.toInt(),
            _underlyingPrice.toUint()
        );
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
     * @notice set `open` flag. Amm is open to trade if `open` is true. Default is false.
     * @dev only owner can call this function
     * @param _open open to trade is true, otherwise is false.
     */
    function setOpen(bool _open) external onlyOwner {
        if (open == _open) return;

        open = _open;
        if (_open) {
            nextFundingTime = ((block.timestamp + fundingPeriod) / 1 hours) * 1 hours;
        }
        emit Open(_open);
    }

    /**
     * @notice set new fee ratio
     * @dev only owner can call
     * @param _feeRatio new ratio
     */
    function setFeeRatio(Decimal.decimal memory _feeRatio) external onlyOwner {
        feeRatio = _feeRatio;
    }

    /**
     * @notice set new trade limit ratio
     * @dev only owner
     * @param _tradeLimitRatio new ratio
     */
    function setTradeLimitRatio(Decimal.decimal memory _tradeLimitRatio) external onlyOwner {
        _requireValidRatio(_tradeLimitRatio);
        tradeLimitRatio = _tradeLimitRatio;
        emit TradeLimitRatioChanged(tradeLimitRatio.toUint());
    }

    /**
     * @notice set fluctuation limit rate. Default value is `1 / max leverage`
     * @dev only owner can call this function
     * @param _fluctuationLimitRatio fluctuation limit rate in 18 digits, 0 means skip the checking
     */
    function setFluctuationLimitRatio(Decimal.decimal memory _fluctuationLimitRatio)
        external
        onlyOwner
    {
        fluctuationLimitRatio = _fluctuationLimitRatio;
        emit FluctuationLimitRatioChanged(fluctuationLimitRatio.toUint());
    }

    /**
     * @notice set init margin ratio
     * @dev only owner can call
     * @param _initMarginRatio new maintenance margin ratio in 18 digits
     */
    function setInitMarginRatio(Decimal.decimal memory _initMarginRatio) external onlyOwner {
        _requireValidRatio(_initMarginRatio);
        initMarginRatio = _initMarginRatio;
        emit InitMarginRatioChanged(initMarginRatio.toUint());
    }

    /**
     * @notice set maintenance margin ratio
     * @dev only owner can call
     * @param _maintenanceMarginRatio new maintenance margin ratio in 18 digits
     */
    function setMaintenanceMarginRatio(Decimal.decimal memory _maintenanceMarginRatio)
        external
        onlyOwner
    {
        _requireValidRatio(_maintenanceMarginRatio);
        maintenanceMarginRatio = _maintenanceMarginRatio;
        emit MaintenanceMarginRatioChanged(maintenanceMarginRatio.toUint());
    }

    /**
     * @notice set the margin ratio after deleveraging
     * @dev only owner can call
     * @param _partialLiquidationRatio new ratio
     */
    function setPartialLiquidationRatio(Decimal.decimal memory _partialLiquidationRatio)
        external
        onlyOwner
    {
        _requireValidRatio(_partialLiquidationRatio);
        // solhint-disable-next-line reason-string
        require(
            _partialLiquidationRatio.cmp(Decimal.one()) < 0,
            "partial liq ratio should be less than 1"
        );
        partialLiquidationRatio = _partialLiquidationRatio;
        emit PartialLiquidationRatioChanged(partialLiquidationRatio.toUint());
    }

    /**
     * @notice set liquidation fee ratio
     * @dev if margin ratio falls below liquidation fee ratio, entire position is liquidated
     * @dev only owner can call
     * @param _liquidationFeeRatio new ratio
     */
    function setLiquidationFeeRatio(Decimal.decimal memory _liquidationFeeRatio)
        external
        onlyOwner
    {
        _requireValidRatio(_liquidationFeeRatio);
        liquidationFeeRatio = _liquidationFeeRatio;
        emit LiquidationFeeRatioChanged(liquidationFeeRatio.toUint());
    }

    /**
     * Set level 1 dynamic fee settings
     * only owner
     * @dev set threshold as 0 to disable
     */
    function setLevel1DynamicFeeSettings(
        Decimal.decimal memory _divergenceThresholdRatio,
        Decimal.decimal memory _feeRatio,
        Decimal.decimal memory _feeInFavorRatio
    ) external onlyOwner {
        level1DynamicFeeSettings = DynamicFeeSettings(
            _divergenceThresholdRatio,
            _feeRatio,
            _feeInFavorRatio
        );
    }

    /**
     * Set level 2 dynamic fee settings
     * only owner
     * @dev set threshold as 0 to disable
     */
    function setLevel2DynamicFeeSettings(
        Decimal.decimal memory _divergenceThresholdRatio,
        Decimal.decimal memory _feeRatio,
        Decimal.decimal memory _feeInFavorRatio
    ) external onlyOwner {
        level2DynamicFeeSettings = DynamicFeeSettings(
            _divergenceThresholdRatio,
            _feeRatio,
            _feeInFavorRatio
        );
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
    ) external onlyOwner {
        maxHoldingBaseAsset = _maxHoldingBaseAsset;
        openInterestNotionalCap = _openInterestNotionalCap;
        emit CapChanged(maxHoldingBaseAsset.toUint(), openInterestNotionalCap.toUint());
    }

    /**
     * @notice set funding period
     * @dev only owner
     * @param _fundingPeriod new funding period
     */
    function setFundingPeriod(uint256 _fundingPeriod) external onlyOwner {
        fundingPeriod = _fundingPeriod;
        fundingBufferPeriod = _fundingPeriod / 2;
        emit FundingPeriodChanged(_fundingPeriod);
    }

    /**
     * @notice set repeg buffer period
     * @dev only owner
     * @param _repegBufferPeriod new repeg buffer period
     */
    function setRepegBufferPeriod(uint256 _repegBufferPeriod) external onlyOwner {
        repegBufferPeriod = _repegBufferPeriod;
    }

    /**
     * @notice set time interval for twap calculation, default is 1 hour
     * @dev only owner can call this function
     * @param _interval time interval in seconds
     */
    function setMarkPriceTwapInterval(uint256 _interval) external onlyOwner {
        require(_interval != 0, "can not set interval to 0");
        markPriceTwapInterval = _interval;
    }

    /**
     * @notice set priceFeed address
     * @dev only owner can call
     * @param _priceFeed new price feed for this AMM
     */
    function setPriceFeed(IPriceFeed _priceFeed) external onlyOwner {
        require(address(_priceFeed) != address(0), "invalid PriceFeed address");
        priceFeed = _priceFeed;
        emit PriceFeedUpdated(address(priceFeed));
    }

    /**
     * @notice dynamic fee mechanism
     * - if trade leaves mark price to be within 2.5% range of index price, then fee percent = 0.3% (standard)
     * - if trade leaves mark price to be over 2.5% range of index price, then fee percent = 1% (surged)
     * - if trade leaves mark price to be over 5.0% range of index price, then fee percent = 5% (surged)
     * - this ensures that traders act towards maintaining peg
     * @notice calculate fees to be levied on the trade
     * @param _dirOfQuote ADD_TO_AMM for long, REMOVE_FROM_AMM for short
     * @param _quoteAssetAmount quoteAssetAmount
     * @return fees fees to be levied on trade
     */
    function calcFee(Dir _dirOfQuote, Decimal.decimal calldata _quoteAssetAmount)
        external
        view
        override
        returns (Decimal.decimal memory fees)
    {
        if (_quoteAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }
        Decimal.decimal memory indexPrice = getIndexPrice();
        Decimal.decimal memory markPrice;
        Decimal.decimal memory baseAssetOut = getInputPrice(_dirOfQuote, _quoteAssetAmount);
        if (_dirOfQuote == Dir.ADD_TO_AMM) {
            markPrice = quoteAssetReserve.addD(_quoteAssetAmount).divD(
                baseAssetReserve.subD(baseAssetOut)
            );
        } else {
            markPrice = quoteAssetReserve.subD(_quoteAssetAmount).divD(
                baseAssetReserve.addD(baseAssetOut)
            );
        }
        /**
         * divergence ratio = abs (index - mark) / index
         */
        uint256 divergenceRatio = MixedDecimal
            .fromDecimal(indexPrice)
            .subD(markPrice)
            .abs()
            .divD(indexPrice)
            .toUint();

        bool isConvergingTrade = (
            markPrice.toUint() < indexPrice.toUint() ? Dir.ADD_TO_AMM : Dir.REMOVE_FROM_AMM
        ) == _dirOfQuote;

        Decimal.decimal memory _feeRatio = feeRatio;

        if (
            level2DynamicFeeSettings.divergenceThresholdRatio.toUint() != 0 && // 0 means unset/disabled
            divergenceRatio > level2DynamicFeeSettings.divergenceThresholdRatio.toUint()
        ) {
            if (isConvergingTrade) _feeRatio = level2DynamicFeeSettings.feeInFavorRatio;
            else _feeRatio = level2DynamicFeeSettings.feeRatio;
        } else if (
            level1DynamicFeeSettings.divergenceThresholdRatio.toUint() != 0 &&
            divergenceRatio > level1DynamicFeeSettings.divergenceThresholdRatio.toUint()
        ) {
            if (isConvergingTrade) _feeRatio = level1DynamicFeeSettings.feeInFavorRatio;
            else _feeRatio = level1DynamicFeeSettings.feeRatio;
        }

        fees = _quoteAssetAmount.mulD(_feeRatio);
    }

    /**
     * @notice get input twap amount.
     * returns how many base asset you will get with the input quote amount based on twap price.
     * @param _dirOfQuote ADD_TO_AMM for long, REMOVE_FROM_AMM for short.
     * @param _quoteAssetAmount quote asset amount
     * @return base asset amount
     */
    function getInputTwap(Dir _dirOfQuote, Decimal.decimal memory _quoteAssetAmount)
        external
        view
        override
        returns (Decimal.decimal memory)
    {
        return
            _implGetInputAssetTwapPrice(
                _dirOfQuote,
                _quoteAssetAmount,
                QuoteAssetDir.QUOTE_IN,
                15 minutes
            );
    }

    /**
     * @notice calculate repeg pnl
     * @param _repegTo price to repeg to
     * @return repegPnl total pnl incurred on vault positions after repeg
     */
    function calcPriceRepegPnl(Decimal.decimal memory _repegTo)
        public
        view
        returns (SignedDecimal.signedDecimal memory repegPnl)
    {
        SignedDecimal.signedDecimal memory y0 = MixedDecimal.fromDecimal(_y0);
        SignedDecimal.signedDecimal memory x0 = MixedDecimal.fromDecimal(_x0);
        SignedDecimal.signedDecimal memory p0 = y0.divD(x0);
        SignedDecimal.signedDecimal memory p1 = MixedDecimal.fromDecimal(getMarkPrice());
        SignedDecimal.signedDecimal memory p2 = MixedDecimal.fromDecimal(_repegTo);
        repegPnl = y0.mulD(
            p2.divD(p1).addD(p1.divD(p0).sqrt()).subD(p2.divD(p1.mulD(p0).sqrt())).subD(
                Decimal.one()
            )
        );
    }

    function calcKRepegPnl(Decimal.decimal memory _k)
        public
        view
        returns (SignedDecimal.signedDecimal memory repegPnl)
    {
        SignedDecimal.signedDecimal memory x0 = MixedDecimal.fromDecimal(_x0);
        SignedDecimal.signedDecimal memory y0 = MixedDecimal.fromDecimal(_y0);
        SignedDecimal.signedDecimal memory p0 = y0.divD(x0);
        SignedDecimal.signedDecimal memory k0 = y0.mulD(x0);
        SignedDecimal.signedDecimal memory p1 = MixedDecimal.fromDecimal(getMarkPrice());
        SignedDecimal.signedDecimal memory k1 = MixedDecimal.fromDecimal(_k);
        SignedDecimal.signedDecimal memory firstDenom = k1
            .divD(p1)
            .sqrt()
            .subD(k0.divD(p1).sqrt())
            .addD(k0.divD(p0).sqrt());
        repegPnl = k1.divD(firstDenom).subD(k1.mulD(p1).sqrt()).subD(k0.mulD(p0).sqrt()).addD(
            k0.mulD(p1).sqrt()
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
        external
        view
        override
        returns (Decimal.decimal memory)
    {
        return
            _implGetInputAssetTwapPrice(
                _dirOfBase,
                _baseAssetAmount,
                QuoteAssetDir.QUOTE_OUT,
                15 minutes
            );
    }

    /**
     * @notice check if close trade goes over fluctuation limit
     * @param _dirOfBase ADD_TO_AMM for closing long, REMOVE_FROM_AMM for closing short
     */
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
        ) = _getPriceBoundariesOfLastBlock();

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

    function getSnapshotLen() external view returns (uint256) {
        return reserveSnapshots.length;
    }

    function getFeeRatio() external view override returns (Decimal.decimal memory) {
        return feeRatio;
    }

    function getInitMarginRatio() external view override returns (Decimal.decimal memory) {
        return initMarginRatio;
    }

    function getMaintenanceMarginRatio() external view override returns (Decimal.decimal memory) {
        return maintenanceMarginRatio;
    }

    function getPartialLiquidationRatio() external view override returns (Decimal.decimal memory) {
        return partialLiquidationRatio;
    }

    function getLiquidationFeeRatio() external view override returns (Decimal.decimal memory) {
        return liquidationFeeRatio;
    }

    /**
     * too avoid too many ratio calls in clearing house
     */
    function getRatios() external view override returns (Ratios memory) {
        return
            Ratios(
                feeRatio,
                initMarginRatio,
                maintenanceMarginRatio,
                partialLiquidationRatio,
                liquidationFeeRatio
            );
    }

    /**
     * @notice get current quote/base asset reserve.
     * @return (quote asset reserve, base asset reserve)
     */
    function getReserves() external view returns (Decimal.decimal memory, Decimal.decimal memory) {
        return (quoteAssetReserve, baseAssetReserve);
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

    function getCumulativeNotional()
        external
        view
        override
        returns (SignedDecimal.signedDecimal memory)
    {
        return cumulativeNotional;
    }

    //
    // PUBLIC
    //

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
     * @notice get mark price based on current quote/base asset reserve.
     * @return mark price
     */
    function getMarkPrice() public view override returns (Decimal.decimal memory) {
        return quoteAssetReserve.divD(baseAssetReserve);
    }

    /**
     * @notice get index price provided by oracle
     * @return index price
     */
    function getIndexPrice() public view override returns (Decimal.decimal memory) {
        return Decimal.decimal(priceFeed.getPrice(priceFeedKey));
    }

    /**
     * @notice get twap price
     */
    function getTwapPrice(uint256 _intervalInSeconds) public view returns (Decimal.decimal memory) {
        return _implGetReserveTwapPrice(_intervalInSeconds);
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
    ) public view override returns (Decimal.decimal memory) {
        if (_quoteAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }

        bool isAddToAmm = _dirOfQuote == Dir.ADD_TO_AMM;

        SignedDecimal.signedDecimal memory baseAssetAfter;
        Decimal.decimal memory quoteAssetAfter;
        Decimal.decimal memory baseAssetBought;

        if (isAddToAmm) {
            quoteAssetAfter = _quoteAssetPoolAmount.addD(_quoteAssetAmount);
        } else {
            quoteAssetAfter = _quoteAssetPoolAmount.subD(_quoteAssetAmount);
        }
        require(quoteAssetAfter.toUint() != 0, "quote asset after is 0");

        baseAssetAfter = MixedDecimal.fromDecimal(k).divD(quoteAssetAfter);
        baseAssetBought = baseAssetAfter.subD(_baseAssetPoolAmount).abs();

        return baseAssetBought;
    }

    function getOutputPriceWithReserves(
        Dir _dirOfBase,
        Decimal.decimal memory _baseAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) public view override returns (Decimal.decimal memory) {
        if (_baseAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }

        bool isAddToAmm = _dirOfBase == Dir.ADD_TO_AMM;

        SignedDecimal.signedDecimal memory quoteAssetAfter;
        Decimal.decimal memory baseAssetAfter;
        Decimal.decimal memory quoteAssetSold;

        if (isAddToAmm) {
            baseAssetAfter = _baseAssetPoolAmount.addD(_baseAssetAmount);
        } else {
            baseAssetAfter = _baseAssetPoolAmount.subD(_baseAssetAmount);
        }
        require(baseAssetAfter.toUint() != 0, "base asset after is 0");

        quoteAssetAfter = MixedDecimal.fromDecimal(k).divD(baseAssetAfter);
        quoteAssetSold = quoteAssetAfter.subD(_quoteAssetPoolAmount).abs();

        return quoteAssetSold;
    }

    //
    // INTERNAL
    //

    function _addReserveSnapshot() internal {
        uint256 currentBlock = block.number;
        ReserveSnapshot storage latestSnapshot = reserveSnapshots[reserveSnapshots.length - 1];
        // update values in snapshot if in the same block
        if (currentBlock == latestSnapshot.blockNumber) {
            latestSnapshot.quoteAssetReserve = quoteAssetReserve;
            latestSnapshot.baseAssetReserve = baseAssetReserve;
        } else {
            reserveSnapshots.push(
                ReserveSnapshot(quoteAssetReserve, baseAssetReserve, block.timestamp, currentBlock)
            );
        }
        emit ReserveSnapshotted(
            quoteAssetReserve.toUint(),
            baseAssetReserve.toUint(),
            block.timestamp
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
        _updateReserve(dirOfQuote, quoteAssetAmount, _baseAssetAmount, true);
        emit SwapOutput(_dirOfBase, quoteAssetAmount.toUint(), _baseAssetAmount.toUint());
        return quoteAssetAmount;
    }

    // the direction is in quote asset
    function _updateReserve(
        Dir _dirOfQuote,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _baseAssetAmount,
        bool _canOverFluctuationLimit
    ) internal {
        // check if it's over fluctuationLimitRatio
        // this check should be before reserves being updated
        _checkIsOverBlockFluctuationLimit(
            _dirOfQuote,
            _quoteAssetAmount,
            _baseAssetAmount,
            _canOverFluctuationLimit
        );

        if (_dirOfQuote == Dir.ADD_TO_AMM) {
            quoteAssetReserve = quoteAssetReserve.addD(_quoteAssetAmount);
            baseAssetReserve = baseAssetReserve.subD(_baseAssetAmount);
            baseAssetDeltaThisFundingPeriod = baseAssetDeltaThisFundingPeriod.subD(
                _baseAssetAmount
            );
            totalPositionSize = totalPositionSize.addD(_baseAssetAmount);
            cumulativeNotional = cumulativeNotional.addD(_quoteAssetAmount);
        } else {
            quoteAssetReserve = quoteAssetReserve.subD(_quoteAssetAmount);
            baseAssetReserve = baseAssetReserve.addD(_baseAssetAmount);
            baseAssetDeltaThisFundingPeriod = baseAssetDeltaThisFundingPeriod.addD(
                _baseAssetAmount
            );
            totalPositionSize = totalPositionSize.subD(_baseAssetAmount);
            cumulativeNotional = cumulativeNotional.subD(_quoteAssetAmount);
        }

        // _addReserveSnapshot must be after checking price fluctuation
        _addReserveSnapshot();
    }

    function _implGetInputAssetTwapPrice(
        Dir _dirOfQuote,
        Decimal.decimal memory _assetAmount,
        QuoteAssetDir _inOut,
        uint256 _interval
    ) internal view returns (Decimal.decimal memory) {
        TwapPriceCalcParams memory params;
        params.opt = TwapCalcOption.INPUT_ASSET;
        params.snapshotIndex = reserveSnapshots.length - 1;
        params.asset.dir = _dirOfQuote;
        params.asset.assetAmount = _assetAmount;
        params.asset.inOrOut = _inOut;
        return _calcTwap(params, _interval);
    }

    function _implGetReserveTwapPrice(uint256 _interval)
        internal
        view
        returns (Decimal.decimal memory)
    {
        TwapPriceCalcParams memory params;
        params.opt = TwapCalcOption.RESERVE_ASSET;
        params.snapshotIndex = reserveSnapshots.length - 1;
        return _calcTwap(params, _interval);
    }

    function _calcTwap(TwapPriceCalcParams memory _params, uint256 _interval)
        internal
        view
        returns (Decimal.decimal memory)
    {
        Decimal.decimal memory currentPrice = _getPriceWithSpecificSnapshot(_params);
        if (_interval == 0) {
            return currentPrice;
        }

        uint256 baseTimestamp = block.timestamp - _interval;
        ReserveSnapshot memory currentSnapshot = reserveSnapshots[_params.snapshotIndex];
        // return the latest snapshot price directly
        // if only one snapshot or the timestamp of latest snapshot is earlier than asking for
        if (reserveSnapshots.length == 1 || currentSnapshot.timestamp <= baseTimestamp) {
            return currentPrice;
        }

        uint256 previousTimestamp = currentSnapshot.timestamp;
        uint256 period = block.timestamp - previousTimestamp;
        Decimal.decimal memory weightedPrice = currentPrice.mulScalar(period);
        while (true) {
            // if snapshot history is too short
            if (_params.snapshotIndex == 0) {
                return weightedPrice.divScalar(period);
            }

            _params.snapshotIndex = _params.snapshotIndex - 1;
            currentSnapshot = reserveSnapshots[_params.snapshotIndex];
            currentPrice = _getPriceWithSpecificSnapshot(_params);

            // check if current round timestamp is earlier than target timestamp
            if (currentSnapshot.timestamp <= baseTimestamp) {
                // weighted time period will be (target timestamp - previous timestamp). For example,
                // now is 1000, _interval is 100, then target timestamp is 900. If timestamp of current round is 970,
                // and timestamp of NEXT round is 880, then the weighted time period will be (970 - 900) = 70,
                // instead of (970 - 880)
                weightedPrice = weightedPrice.addD(
                    currentPrice.mulScalar(previousTimestamp - baseTimestamp)
                );
                break;
            }

            uint256 timeFraction = previousTimestamp - currentSnapshot.timestamp;
            weightedPrice = weightedPrice.addD(currentPrice.mulScalar(timeFraction));
            period = period + timeFraction;
            previousTimestamp = currentSnapshot.timestamp;
        }
        return weightedPrice.divScalar(_interval);
    }

    function _getPriceWithSpecificSnapshot(TwapPriceCalcParams memory params)
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

    function _getPriceBoundariesOfLastBlock()
        internal
        view
        returns (Decimal.decimal memory, Decimal.decimal memory)
    {
        uint256 len = reserveSnapshots.length;
        ReserveSnapshot memory latestSnapshot = reserveSnapshots[len - 1];
        // if the latest snapshot is the same as current block, get the previous one
        if (latestSnapshot.blockNumber == block.number && len > 1) {
            latestSnapshot = reserveSnapshots[len - 2];
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
    function _checkIsOverBlockFluctuationLimit(
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
        ) = _getPriceBoundariesOfLastBlock();

        Decimal.decimal memory price = quoteAssetReserve.divD(baseAssetReserve);
        // solhint-disable-next-line reason-string
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

    function _requireValidRatio(Decimal.decimal memory _ratio) internal pure {
        require(_ratio.cmp(Decimal.one()) <= 0, "invalid ratio");
    }
}

