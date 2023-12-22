// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./FixedPointMathLib.sol";
import {TransferHelper} from "./TransferHelper.sol";
import "./SafeCast.sol";
import "./ReentrancyGuard.sol";
import "./IStrategyVault.sol";
import "./IPredyTradeCallback.sol";
import "./BaseStrategy.sol";
import "./Constants.sol";
import "./UniHelper.sol";
import "./Reader.sol";

/**
 * Error Codes
 * GSS0: already initialized
 * GSS1: not initialized
 * GSS2: required margin amount must be less than maximum
 * GSS3: withdrawn margin amount must be greater than minimum
 * GSS4: invalid leverage
 * GSS5: caller must be Controller
 */
contract GammaShortStrategy is BaseStrategy, ReentrancyGuard, IStrategyVault, IPredyTradeCallback {
    using SafeCast for uint256;
    using SafeCast for int256;

    Reader internal reader;

    uint256 private constant SHARE_SCALER = 1e18;

    uint256 private constant DEFAULT_AMOUNT_IN_CACHED = type(uint256).max;

    uint256 finalDepositAmountCached;

    uint256 public lastHedgeTimestamp;

    uint256 public lastHedgePrice;

    uint256 private hedgeSqrtPriceThreshold;

    uint256 private hedgeInterval;

    address public hedger;

    event HedgerUpdated(address newHedgerAddress);
    event DepositedToStrategy(address indexed account, uint256 strategyTokenAmount, uint256 depositedAmount);
    event WithdrawnFromStrategy(address indexed account, uint256 strategyTokenAmount, uint256 withdrawnAmount);

    event HedgePriceThresholdUpdated(uint256 hedgeSqrtPriceThreshold);
    event HedgeIntervalUpdated(uint256 hedgeInterval);

    event DeltaHedged(int256 delta);

    modifier onlyHedger() {
        require(hedger == msg.sender, "GSS: caller is not hedger");
        _;
    }

    constructor() {}

    function initialize(
        address _controller,
        address _reader,
        uint256 _assetId,
        MinPerValueLimit memory _minPerValueLimit,
        string memory _name,
        string memory _symbol
    ) public initializer {
        BaseStrategy.initialize(_controller, _assetId, _minPerValueLimit, _name, _symbol);
        reader = Reader(_reader);

        // square root of 7.5% scaled by 1e18
        hedgeSqrtPriceThreshold = 10368220676 * 1e8;

        hedgeInterval = 2 days;

        // initialize last sqrt price and timestamp
        lastHedgePrice = controller.getSqrtPrice(_assetId);
        lastHedgeTimestamp = block.timestamp;
    }

    function decimals() public view override returns (uint8) {
        return 6;
    }

    /**
     * @dev Callback for Predy Controller
     */
    function predyTradeCallback(DataType.TradeResult memory _tradeResult, bytes calldata _data)
        external
        override(IPredyTradeCallback)
        returns (int256)
    {
        require(msg.sender == address(controller), "GSS5");

        (uint256 share, address caller, bool isQuoteMode) = abi.decode(_data, (uint256, address, bool));

        (int256 entryUpdate, int256 entryValue, uint256 totalMargin) = calEntryValue(_tradeResult.payoff);

        uint256 finalDepositMargin = calShareToMargin(entryUpdate, entryValue, share, totalMargin);

        finalDepositMargin = roundUpMargin(finalDepositMargin, Constants.MARGIN_ROUNDED_DECIMALS);

        finalDepositAmountCached = finalDepositMargin;

        if (isQuoteMode) {
            revertMarginAmount(finalDepositMargin);
        }

        TransferHelper.safeTransferFrom(usdc, caller, address(this), finalDepositMargin);

        ERC20(usdc).approve(address(controller), finalDepositMargin);

        return int256(finalDepositMargin);
    }

    ////////////////////////
    // Operator Functions //
    ////////////////////////

    /**
     * @notice Sets new hedger address
     * @dev Only operator can call this function.
     * @param _newHedger The address of new hedger
     */
    function setHedger(address _newHedger) external onlyOperator {
        require(_newHedger != address(0));
        hedger = _newHedger;

        emit HedgerUpdated(_newHedger);
    }

    /**
     * @notice deposit for the position initialization
     * @dev The function can be called by owner.
     * @param _initialMarginAmount initial margin amount
     * @param _initialPerpAmount initial perp amount
     * @param _initialSquartAmount initial squart amount
     * @param _tradeParams trade parameters
     */
    function depositForPositionInitialization(
        uint256 _initialMarginAmount,
        int256 _initialPerpAmount,
        int256 _initialSquartAmount,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) external onlyOperator nonReentrant {
        require(totalSupply() == 0, "GSS0");

        TransferHelper.safeTransferFrom(usdc, msg.sender, address(this), _initialMarginAmount);

        ERC20(usdc).approve(address(controller), _initialMarginAmount);

        vaultId = controller.updateMargin(int256(_initialMarginAmount));

        controller.tradePerp(
            vaultId,
            assetId,
            TradeLogic.TradeParams(
                _initialPerpAmount,
                _initialSquartAmount,
                _tradeParams.lowerSqrtPrice,
                _tradeParams.upperSqrtPrice,
                _tradeParams.deadline,
                false,
                ""
            )
        );

        _mint(msg.sender, _initialMarginAmount);

        emit DepositedToStrategy(msg.sender, _initialMarginAmount, _initialMarginAmount);
    }

    /**
     * @notice Updates price threshold for delta hedging.
     * @param _newSqrtPriceThreshold New square root price threshold
     */
    function updateHedgePriceThreshold(uint256 _newSqrtPriceThreshold) external onlyOperator {
        require(1e18 <= _newSqrtPriceThreshold && _newSqrtPriceThreshold < 2 * 1e18);

        hedgeSqrtPriceThreshold = _newSqrtPriceThreshold;

        emit HedgePriceThresholdUpdated(_newSqrtPriceThreshold);
    }

    /**
     * @notice Updates interval for delta hedging.
     * @param _hedgeInterval New interval
     */
    function updateHedgeInterval(uint256 _hedgeInterval) external onlyOperator {
        require(1 hours <= _hedgeInterval && _hedgeInterval <= 2 weeks);

        hedgeInterval = _hedgeInterval;

        emit HedgeIntervalUpdated(_hedgeInterval);
    }

    /**
     * @notice Changes gamma size per share.
     * @param _squartAmount squart amount
     * @param _tradeParams trade parameters
     */
    function updateGamma(int256 _squartAmount, IStrategyVault.StrategyTradeParams memory _tradeParams)
        external
        onlyOperator
    {
        controller.tradePerp(
            vaultId,
            assetId,
            TradeLogic.TradeParams(
                0,
                _squartAmount,
                _tradeParams.lowerSqrtPrice,
                _tradeParams.upperSqrtPrice,
                _tradeParams.deadline,
                false,
                ""
            )
        );

        uint256 minPerVaultValue = getMinPerVaultValue();

        require(minPerValueLimit.lower <= minPerVaultValue && minPerVaultValue <= minPerValueLimit.upper, "GSS4");
    }

    /**
     * @notice Hedger can call the delta hedging function if the price has changed by a set ratio
     * from the last price at the hedging or time has elapsed by a set interval since the last hedge time.
     * @param _tradeParams Trade parameters for Predy contract
     */
    function execDeltaHedge(IStrategyVault.StrategyTradeParams memory _tradeParams, uint256 _deltaRatio)
        external
        onlyHedger
        nonReentrant
    {
        uint256 sqrtPrice = controller.getSqrtPrice(assetId);

        require(isTimeHedge() || isPriceHedge(sqrtPrice), "TG");

        _execDeltaHedge(_tradeParams, _deltaRatio);

        if (_deltaRatio == 1e18) {
            lastHedgePrice = sqrtPrice;
            lastHedgeTimestamp = block.timestamp;
        }
    }

    //////////////////////
    //  User Functions  //
    //////////////////////

    /**
     * @notice Deposits margin and mints strategy token.
     * @param _strategyTokenAmount strategy token amount to mint
     * @param _recepient recepient address of strategy token
     * @param _maxDepositAmount maximum USDC amount that caller deposits
     * @param isQuoteMode is quote mode or not
     * @param _tradeParams trade parameters
     * @return finalDepositMargin USDC amount that caller actually deposits
     */
    function deposit(
        uint256 _strategyTokenAmount,
        address _recepient,
        uint256 _maxDepositAmount,
        bool isQuoteMode,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) external override nonReentrant returns (uint256 finalDepositMargin) {
        require(totalSupply() > 0, "GSS1");

        uint256 share = calMintToShare(_strategyTokenAmount, totalSupply());

        DataType.Vault memory vault = controller.getVault(vaultId);

        int256 tradePerp = calShareToMint(share, vault.openPositions[0].perpTrade.perp.amount);
        int256 tradeSqrt = calShareToMint(share, vault.openPositions[0].perpTrade.sqrtPerp.amount);

        controller.tradePerp(
            vaultId,
            assetId,
            TradeLogic.TradeParams(
                tradePerp,
                tradeSqrt,
                _tradeParams.lowerSqrtPrice,
                _tradeParams.upperSqrtPrice,
                _tradeParams.deadline,
                true,
                abi.encode(share, msg.sender, isQuoteMode)
            )
        );

        finalDepositMargin = finalDepositAmountCached;

        finalDepositAmountCached = DEFAULT_AMOUNT_IN_CACHED;

        require(finalDepositMargin <= _maxDepositAmount, "GSS2");

        _mint(_recepient, _strategyTokenAmount);

        {
            DataType.AssetStatus memory asset = controller.getAsset(assetId);

            UniHelper.checkPriceByTWAP(asset.sqrtAssetStatus.uniswapPool);
        }

        emit DepositedToStrategy(_recepient, _strategyTokenAmount, finalDepositMargin);
    }

    /**
     * @notice Withdraws margin and burns strategy token.
     * @param _withdrawStrategyAmount strategy token amount to burn
     * @param _recepient recepient address of stable token
     * @param _minWithdrawAmount minimum USDC amount that caller deposits
     * @param _tradeParams trade parameters
     * @return finalWithdrawAmount USDC amount that caller actually withdraws
     */
    function withdraw(
        uint256 _withdrawStrategyAmount,
        address _recepient,
        int256 _minWithdrawAmount,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) external nonReentrant returns (uint256 finalWithdrawAmount) {
        uint256 strategyShare = _withdrawStrategyAmount * SHARE_SCALER / totalSupply();

        DataType.Vault memory vault = controller.getVault(vaultId);

        DataType.TradeResult memory tradeResult = controller.tradePerp(
            vaultId,
            assetId,
            TradeLogic.TradeParams(
                -int256(strategyShare) * vault.openPositions[0].perpTrade.perp.amount / int256(SHARE_SCALER),
                -int256(strategyShare) * vault.openPositions[0].perpTrade.sqrtPerp.amount / int256(SHARE_SCALER),
                _tradeParams.lowerSqrtPrice,
                _tradeParams.upperSqrtPrice,
                _tradeParams.deadline,
                false,
                ""
            )
        );

        // Calculates realized and unrealized PnL.
        int256 withdrawMarginAmount = (vault.margin + tradeResult.fee) * int256(strategyShare) / int256(SHARE_SCALER)
            + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        require(withdrawMarginAmount >= _minWithdrawAmount && _minWithdrawAmount >= 0, "GSS3");

        _burn(msg.sender, _withdrawStrategyAmount);

        finalWithdrawAmount = roundDownMargin(uint256(withdrawMarginAmount), Constants.MARGIN_ROUNDED_DECIMALS);

        controller.updateMargin(-int256(finalWithdrawAmount));

        TransferHelper.safeTransfer(usdc, _recepient, finalWithdrawAmount);

        emit WithdrawnFromStrategy(_recepient, _withdrawStrategyAmount, finalWithdrawAmount);
    }

    /**
     * @notice Gets price of strategy token by USDC.
     * @dev The function should not be called on chain.
     */
    function getPrice() external returns (uint256) {
        DataType.VaultStatusResult memory vaultStatusResult = controller.getVaultStatus(vaultId);

        if (vaultStatusResult.vaultValue <= 0) {
            return 0;
        }

        return uint256(vaultStatusResult.vaultValue) * SHARE_SCALER / totalSupply();
    }

    function getDelta() external view returns (int256) {
        return reader.getDelta(assetId, vaultId);
    }

    function checkPriceHedge() external view returns (bool) {
        return isPriceHedge(controller.getSqrtPrice(assetId));
    }

    function checkTimeHedge() external view returns (bool) {
        return isTimeHedge();
    }

    ///////////////////////
    // Private Functions //
    ///////////////////////

    function isPriceHedge(uint256 _sqrtPrice) internal view returns (bool) {
        uint256 lower = lastHedgePrice * Constants.ONE / hedgeSqrtPriceThreshold;

        uint256 upper = lastHedgePrice * hedgeSqrtPriceThreshold / Constants.ONE;

        return _sqrtPrice < lower || upper < _sqrtPrice;
    }

    function isTimeHedge() internal view returns (bool) {
        return lastHedgeTimestamp + hedgeInterval < block.timestamp;
    }

    function getMinPerVaultValue() internal returns (uint256) {
        DataType.VaultStatusResult memory vaultStatusResult = controller.getVaultStatus(vaultId);

        return SafeCast.toUint256(vaultStatusResult.minDeposit * 1e18 / vaultStatusResult.vaultValue);
    }

    function _execDeltaHedge(IStrategyVault.StrategyTradeParams memory _tradeParams, uint256 _deltaRatio) internal {
        require(_deltaRatio <= 1e18);

        int256 delta = reader.getDelta(assetId, vaultId) * int256(_deltaRatio) / 1e18;

        controller.tradePerp(
            vaultId,
            assetId,
            TradeLogic.TradeParams(
                -delta, 0, _tradeParams.lowerSqrtPrice, _tradeParams.upperSqrtPrice, _tradeParams.deadline, false, ""
            )
        );

        emit DeltaHedged(delta);
    }

    function calEntryValue(Perp.Payoff memory payoff)
        internal
        view
        returns (int256 entryUpdate, int256 entryValue, uint256 totalMargin)
    {
        DataType.Vault memory vault = controller.getVault(vaultId);

        DataType.UserStatus memory userStatus = vault.openPositions[0];

        entryUpdate = payoff.perpEntryUpdate + payoff.sqrtEntryUpdate + payoff.sqrtRebalanceEntryUpdateStable;

        entryValue = userStatus.perpTrade.perp.entryValue + userStatus.perpTrade.sqrtPerp.entryValue
            + userStatus.perpTrade.sqrtPerp.stableRebalanceEntryValue;

        totalMargin = uint256(vault.margin);
    }

    function calMintToShare(uint256 _mint, uint256 _total) internal pure returns (uint256) {
        return _mint * SHARE_SCALER / (_total + _mint);
    }

    function calShareToMint(uint256 _share, int256 _total) internal pure returns (int256) {
        return _total * _share.toInt256() / (SHARE_SCALER - _share).toInt256();
    }

    function calShareToMargin(int256 _entryUpdate, int256 _entryValue, uint256 _share, uint256 _totalMarginBefore)
        internal
        pure
        returns (uint256)
    {
        uint256 t = SafeCast.toUint256(
            _share.toInt256() * (_totalMarginBefore.toInt256() + _entryValue) / int256(SHARE_SCALER) - _entryUpdate
        );

        return t * SHARE_SCALER / (SHARE_SCALER - _share);
    }

    function roundUpMargin(uint256 _amount, uint256 _roundedDecimals) internal pure returns (uint256) {
        return FixedPointMathLib.mulDivUp(_amount, 1, _roundedDecimals) * _roundedDecimals;
    }

    function roundDownMargin(uint256 _amount, uint256 _roundedDecimals) internal pure returns (uint256) {
        return FixedPointMathLib.mulDivDown(_amount, 1, _roundedDecimals) * _roundedDecimals;
    }

    function revertMarginAmount(uint256 _marginAmount) internal pure {
        assembly {
            let ptr := mload(0x20)
            mstore(ptr, _marginAmount)
            mstore(add(ptr, 0x20), 0)
            mstore(add(ptr, 0x40), 0)
            revert(ptr, 96)
        }
    }
}

