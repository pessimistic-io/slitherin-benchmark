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

    Reader public reader;

    uint256 private constant SHARE_SCALER = 1e18;

    uint256 private constant DEFAULT_AMOUNT_IN_CACHED = type(uint256).max;

    uint256 finalDepositAmountCached;

    address public hedger;

    event HedgerUpdated(address newHedgerAddress);
    event ReaderUpdated(address newReaderAddress);
    event DepositedToStrategy(
        uint256 strategyId, address indexed account, uint256 strategyTokenAmount, uint256 depositedAmount
    );
    event WithdrawnFromStrategy(
        uint256 strategyId, address indexed account, uint256 strategyTokenAmount, uint256 withdrawnAmount
    );

    event HedgePriceThresholdUpdated(uint256 strategyId, uint256 hedgeSqrtPriceThreshold);
    event HedgeIntervalUpdated(uint256 strategyId, uint256 hedgeInterval);

    event DeltaHedged(uint256 strategyId, int256 delta);

    modifier onlyHedger() {
        require(hedger == msg.sender, "GSS: caller is not hedger");
        _;
    }

    constructor() {}

    function initialize(address _controller, address _reader, MinPerValueLimit memory _minPerValueLimit)
        public
        initializer
    {
        BaseStrategy.initialize(_controller, _minPerValueLimit);
        reader = Reader(_reader);
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

        (uint256 share, address caller, bool isQuoteMode, uint256 strategyId) =
            abi.decode(_data, (uint256, address, bool, uint256));

        Strategy memory strategy = strategies[strategyId];

        (int256 entryUpdate, int256 entryValue, uint256 totalMargin) =
            calEntryValue(_tradeResult.payoff, strategy.vaultId);

        uint256 finalDepositMargin = calShareToMargin(entryUpdate, entryValue, share, totalMargin);

        finalDepositMargin = roundUpMargin(finalDepositMargin, strategy.marginRoundedScaler);

        finalDepositAmountCached = finalDepositMargin;

        if (isQuoteMode) {
            revertMarginAmount(finalDepositMargin);
        }

        TransferHelper.safeTransferFrom(strategy.marginToken, caller, address(this), finalDepositMargin);

        ERC20(strategy.marginToken).approve(address(controller), finalDepositMargin);

        return int256(finalDepositMargin);
    }

    ////////////////////////
    // Operator Functions //
    ////////////////////////

    function setReader(address _reader) external onlyOperator {
        require(_reader != address(0));

        reader = Reader(_reader);

        emit ReaderUpdated(_reader);
    }

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
     * @param _sqrtPriceThreshold hedge threshold
     */
    function depositForPositionInitialization(
        uint256 _strategyId,
        uint64 _pairId,
        uint256 _initialMarginAmount,
        int256 _initialPerpAmount,
        int256 _initialSquartAmount,
        IStrategyVault.StrategyTradeParams memory _tradeParams,
        uint256 _sqrtPriceThreshold
    ) external onlyOperator nonReentrant returns (uint256) {
        Strategy storage strategy = addOrGetStrategy(_strategyId, _pairId);

        require(totalSupply(strategy) == 0, "GSS0");

        saveHedgePriceThreshold(strategy, _sqrtPriceThreshold);

        TransferHelper.safeTransferFrom(strategy.marginToken, msg.sender, address(this), _initialMarginAmount);

        ERC20(strategy.marginToken).approve(address(controller), _initialMarginAmount);

        strategy.vaultId = controller.updateMarginOfIsolated(
            strategy.pairGroupId, strategy.vaultId, int256(_initialMarginAmount), false
        );

        controller.setAutoTransfer(strategy.vaultId, true);

        controller.tradePerp(
            strategy.vaultId,
            strategy.pairId,
            TradePerpLogic.TradeParams(
                _initialPerpAmount,
                _initialSquartAmount,
                _tradeParams.lowerSqrtPrice,
                _tradeParams.upperSqrtPrice,
                _tradeParams.deadline,
                false,
                ""
            )
        );

        SupplyToken(strategy.strategyToken).mint(msg.sender, _initialMarginAmount);

        emit DepositedToStrategy(strategy.id, msg.sender, _initialMarginAmount, _initialMarginAmount);

        return strategy.id;
    }

    /**
     * @notice Updates price threshold for delta hedging.
     * @param _newSqrtPriceThreshold New square root price threshold
     */
    function updateHedgePriceThreshold(uint256 _strategyId, uint256 _newSqrtPriceThreshold) external onlyOperator {
        validateStrategyId(_strategyId);

        saveHedgePriceThreshold(strategies[_strategyId], _newSqrtPriceThreshold);
    }

    /**
     * @notice Updates interval for delta hedging.
     * @param _hedgeInterval New interval
     */
    function updateHedgeInterval(uint256 _strategyId, uint256 _hedgeInterval) external onlyOperator {
        validateStrategyId(_strategyId);
        require(1 hours <= _hedgeInterval && _hedgeInterval <= 2 weeks);

        strategies[_strategyId].hedgeStatus.hedgeInterval = _hedgeInterval;

        emit HedgeIntervalUpdated(_strategyId, _hedgeInterval);
    }

    /**
     * @notice Changes gamma size per share.
     * @param _sqrtAmount squart amount
     * @param _tradeParams trade parameters
     */
    function updateGamma(
        uint256 _strategyId,
        int256 _sqrtAmount,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) external onlyOperator {
        validateStrategyId(_strategyId);
        Strategy memory strategy = strategies[_strategyId];

        uint256 sqrtPrice = controller.getSqrtPrice(strategy.pairId);
        int256 perpAmount = -ReaderLogic.calculateDelta(sqrtPrice, _sqrtAmount, 0);

        controller.tradePerp(
            strategy.vaultId,
            strategy.pairId,
            TradePerpLogic.TradeParams(
                perpAmount,
                _sqrtAmount,
                _tradeParams.lowerSqrtPrice,
                _tradeParams.upperSqrtPrice,
                _tradeParams.deadline,
                false,
                ""
            )
        );

        uint256 minPerVaultValue = getMinPerVaultValue(strategy.vaultId);

        require(minPerValueLimit.lower <= minPerVaultValue && minPerVaultValue <= minPerValueLimit.upper, "GSS4");
    }

    /**
     * @notice Hedger can call the delta hedging function if the price has changed by a set ratio
     * from the last price at the hedging or time has elapsed by a set interval since the last hedge time.
     * @param _tradeParams Trade parameters for Predy contract
     */
    function execDeltaHedge(
        uint256 _strategyId,
        IStrategyVault.StrategyTradeParams memory _tradeParams,
        uint256 _deltaRatio
    ) external onlyHedger nonReentrant {
        validateStrategyId(_strategyId);
        Strategy storage strategy = strategies[_strategyId];

        uint256 sqrtPrice = controller.getSqrtPrice(strategy.pairId);

        require(isTimeHedge(strategy.hedgeStatus) || isPriceHedge(strategy.hedgeStatus, sqrtPrice), "TG");

        _execDeltaHedge(strategy, _tradeParams, _deltaRatio);

        if (_deltaRatio == 1e18) {
            strategy.hedgeStatus.lastHedgePrice = sqrtPrice;
            strategy.hedgeStatus.lastHedgeTimestamp = block.timestamp;
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
        uint256 _strategyId,
        uint256 _strategyTokenAmount,
        address _recepient,
        uint256 _maxDepositAmount,
        bool isQuoteMode,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) external override nonReentrant returns (uint256 finalDepositMargin) {
        validateStrategyId(_strategyId);
        Strategy memory strategy = strategies[_strategyId];

        require(totalSupply(strategy) > 0, "GSS1");

        TradePerpLogic.TradeParams memory tradeParams =
            createTradeParams(strategy, _strategyTokenAmount, isQuoteMode, _tradeParams);

        controller.tradePerp(strategy.vaultId, strategy.pairId, tradeParams);

        finalDepositMargin = finalDepositAmountCached;

        finalDepositAmountCached = DEFAULT_AMOUNT_IN_CACHED;

        require(finalDepositMargin <= _maxDepositAmount, "GSS2");

        SupplyToken(strategy.strategyToken).mint(_recepient, _strategyTokenAmount);

        {
            DataType.PairStatus memory asset = controller.getAsset(strategy.pairId);

            UniHelper.checkPriceByTWAP(asset.sqrtAssetStatus.uniswapPool);
        }

        emit DepositedToStrategy(_strategyId, _recepient, _strategyTokenAmount, finalDepositMargin);
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
        uint256 _strategyId,
        uint256 _withdrawStrategyAmount,
        address _recepient,
        int256 _minWithdrawAmount,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) external nonReentrant returns (uint256 finalWithdrawAmount) {
        validateStrategyId(_strategyId);
        Strategy memory strategy = strategies[_strategyId];

        uint256 strategyShare = _withdrawStrategyAmount * SHARE_SCALER / totalSupply(strategy);

        DataType.Vault memory vault = controller.getVault(strategy.vaultId);

        DataType.TradeResult memory tradeResult = controller.tradePerp(
            strategy.vaultId,
            strategy.pairId,
            TradePerpLogic.TradeParams(
                -int256(strategyShare) * vault.openPositions[0].perp.amount / int256(SHARE_SCALER),
                -int256(strategyShare) * vault.openPositions[0].sqrtPerp.amount / int256(SHARE_SCALER),
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

        SupplyToken(strategy.strategyToken).burn(msg.sender, _withdrawStrategyAmount);

        finalWithdrawAmount = roundDownMargin(uint256(withdrawMarginAmount), strategy.marginRoundedScaler);

        controller.updateMarginOfIsolated(strategy.pairGroupId, strategy.vaultId, -int256(finalWithdrawAmount), false);

        TransferHelper.safeTransfer(strategy.marginToken, _recepient, finalWithdrawAmount);

        emit WithdrawnFromStrategy(_strategyId, _recepient, _withdrawStrategyAmount, finalWithdrawAmount);
    }

    /**
     * @notice Gets price of strategy token by USDC.
     * @dev The function should not be called on chain.
     */
    function getPrice(uint256 _strategyId) external returns (uint256) {
        validateStrategyId(_strategyId);

        Strategy memory strategy = strategies[_strategyId];

        DataType.VaultStatusResult memory vaultStatusResult = controller.getVaultStatus(strategy.vaultId);

        if (vaultStatusResult.vaultValue <= 0) {
            return 0;
        }

        return uint256(vaultStatusResult.vaultValue) * SHARE_SCALER / totalSupply(strategy);
    }

    function getDelta(uint256 _strategyId) external view returns (int256) {
        validateStrategyId(_strategyId);

        Strategy memory strategy = strategies[_strategyId];

        return reader.getDelta(strategy.pairId, strategy.vaultId);
    }

    function checkPriceHedge(uint256 _strategyId) external view returns (bool) {
        validateStrategyId(_strategyId);

        Strategy memory strategy = strategies[_strategyId];

        return isPriceHedge(strategy.hedgeStatus, controller.getSqrtPrice(strategy.pairId));
    }

    function checkTimeHedge(uint256 _strategyId) external view returns (bool) {
        validateStrategyId(_strategyId);

        return isTimeHedge(strategies[_strategyId].hedgeStatus);
    }

    function getTotalSupply(uint256 _strategyId) external view returns (uint256) {
        return totalSupply(strategies[_strategyId]);
    }

    ///////////////////////
    // Private Functions //
    ///////////////////////

    function saveHedgePriceThreshold(Strategy storage _strategy, uint256 _newSqrtPriceThreshold) internal {
        require(1e18 <= _newSqrtPriceThreshold && _newSqrtPriceThreshold < 2 * 1e18);

        _strategy.hedgeStatus.hedgeSqrtPriceThreshold = _newSqrtPriceThreshold;

        emit HedgePriceThresholdUpdated(_strategy.id, _newSqrtPriceThreshold);
    }

    function createTradeParams(
        Strategy memory _strategy,
        uint256 _strategyTokenAmount,
        bool _isQuoteMode,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) internal view returns (TradePerpLogic.TradeParams memory) {
        int256 tradePerp;
        int256 tradeSqrt;
        bytes memory data;
        {
            uint256 share = calMintToShare(_strategyTokenAmount, totalSupply(_strategy));

            DataType.Vault memory vault = controller.getVault(_strategy.vaultId);

            tradePerp = calShareToMint(share, vault.openPositions[0].perp.amount);
            tradeSqrt = calShareToMint(share, vault.openPositions[0].sqrtPerp.amount);

            data = abi.encode(share, msg.sender, _isQuoteMode, _strategy.id);
        }

        return TradePerpLogic.TradeParams(
            tradePerp,
            tradeSqrt,
            _tradeParams.lowerSqrtPrice,
            _tradeParams.upperSqrtPrice,
            _tradeParams.deadline,
            true,
            data
        );
    }

    function isPriceHedge(HedgeStatus memory _hedgeStatus, uint256 _sqrtPrice) internal pure returns (bool) {
        uint256 lower = _hedgeStatus.lastHedgePrice * Constants.ONE / _hedgeStatus.hedgeSqrtPriceThreshold;

        uint256 upper = _hedgeStatus.lastHedgePrice * _hedgeStatus.hedgeSqrtPriceThreshold / Constants.ONE;

        return _sqrtPrice < lower || upper < _sqrtPrice;
    }

    function isTimeHedge(HedgeStatus memory _hedgeStatus) internal view returns (bool) {
        return _hedgeStatus.lastHedgeTimestamp + _hedgeStatus.hedgeInterval < block.timestamp;
    }

    function getMinPerVaultValue(uint256 _vaultId) internal returns (uint256) {
        DataType.VaultStatusResult memory vaultStatusResult = controller.getVaultStatus(_vaultId);

        return SafeCast.toUint256(vaultStatusResult.minDeposit * 1e18 / vaultStatusResult.vaultValue);
    }

    function totalSupply(Strategy memory _strategy) internal view returns (uint256) {
        return ERC20(_strategy.strategyToken).totalSupply();
    }

    function _execDeltaHedge(
        Strategy memory strategy,
        IStrategyVault.StrategyTradeParams memory _tradeParams,
        uint256 _deltaRatio
    ) internal {
        require(_deltaRatio <= 1e18);

        int256 delta = reader.getDelta(strategy.pairId, strategy.vaultId) * int256(_deltaRatio) / 1e18;

        controller.tradePerp(
            strategy.vaultId,
            strategy.pairId,
            TradePerpLogic.TradeParams(
                -delta, 0, _tradeParams.lowerSqrtPrice, _tradeParams.upperSqrtPrice, _tradeParams.deadline, false, ""
            )
        );

        emit DeltaHedged(strategy.id, delta);
    }

    function calEntryValue(Perp.Payoff memory payoff, uint256 _vaultId)
        internal
        view
        returns (int256 entryUpdate, int256 entryValue, uint256 totalMargin)
    {
        DataType.Vault memory vault = controller.getVault(_vaultId);

        Perp.UserStatus memory userStatus = vault.openPositions[0];

        entryUpdate = payoff.perpEntryUpdate + payoff.sqrtEntryUpdate + payoff.sqrtRebalanceEntryUpdateStable;

        entryValue =
            userStatus.perp.entryValue + userStatus.sqrtPerp.entryValue + userStatus.sqrtPerp.stableRebalanceEntryValue;

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

