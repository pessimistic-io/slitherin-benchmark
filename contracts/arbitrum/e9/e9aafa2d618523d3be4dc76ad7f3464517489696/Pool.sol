// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {IERC20Metadata} from "./extensions_IERC20Metadata.sol";
import {IERC20} from "./ERC20_IERC20.sol";
import {SignedIntMath} from "./SignedIntMath.sol";
import {MathUtils} from "./MathUtils.sol";
import {PositionLogic} from "./PositionLogic.sol";
import {ILevelOracle} from "./ILevelOracle.sol";
import {ILPToken} from "./ILPToken.sol";
import {IPool} from "./IPool.sol";
import {ILiquidityCalculator} from "./ILiquidityCalculator.sol";
import {IInterestRateModel} from "./IInterestRateModel.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {IPoolHook} from "./IPoolHook.sol";
import {SafeCast} from "./SafeCast.sol";
import {DataTypes} from "./DataTypes.sol";
import {Constants} from "./Constants.sol";
import {SafeERC20} from "./SafeERC20.sol";

uint256 constant USD_VALUE_DECIMAL = 30;

contract Pool is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PoolStorage, IPool {
    using SignedIntMath for int256;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

    struct IncreasePositionVars {
        uint256 reserveAdded;
        uint256 collateralAmount;
        uint256 collateralValueAdded;
        uint256 feeValue;
        uint256 daoFee;
        uint256 indexPrice;
        uint256 sizeChanged;
        uint256 feeAmount;
        uint256 totalLpFee;
    }

    /// @notice common variable used accross decrease process
    struct DecreasePositionVars {
        /// @notice santinized input: collateral value able to be withdraw
        uint256 collateralReduced;
        /// @notice santinized input: position size to decrease, capped to position's size
        uint256 sizeChanged;
        /// @notice current price of index
        uint256 indexPrice;
        /// @notice current price of collateral
        uint256 collateralPrice;
        /// @notice postion's remaining collateral value in USD after decrease position
        uint256 remainingCollateral;
        /// @notice reserve reduced due to reducion process
        uint256 reserveReduced;
        /// @notice total value of fee to be collect (include dao fee and LP fee)
        uint256 feeValue;
        /// @notice amount of collateral taken as fee
        uint256 daoFee;
        /// @notice real transfer out amount to user
        uint256 payout;
        /// @notice 'net' PnL (fee not counted)
        int256 pnl;
        int256 poolAmountReduced;
        uint256 totalLpFee;
    }

    /* =========== MODIFIERS ========== */
    modifier onlyOrderManager() {
        _requireOrderManager();
        _;
    }

    modifier onlyAsset(address _token) {
        _validateAsset(_token);
        _;
    }

    modifier onlyListedToken(address _token) {
        _requireListedToken(_token);
        _;
    }

    modifier onlyController() {
        _onlyController();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /* ======== INITIALIZERS ========= */
    function initialize(uint256 _maxLeverage, uint256 _maintainanceMargin, uint256 _interestAccrualInterval) external initializer {
        if (_interestAccrualInterval == 0) {
            revert InvalidInterval();
        }
        __Ownable_init();
        __ReentrancyGuard_init();
        _setMaxLeverage(_maxLeverage);
        _setMaintenanceMargin(_maintainanceMargin);
        daoFee = Constants.PRECISION;
        accrualInterval = _interestAccrualInterval;
    }

    // ========= View functions =========

    function isValidLeverageTokenPair(
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side,
        bool _isIncrease
    ) external view returns (bool) {
        return _isValidLeverageTokenPair(_indexToken, _collateralToken, _side, _isIncrease);
    }

    function canSwap(address _tokenIn, address _tokenOut) public view returns (bool) {
        return isAsset[_tokenOut] && isListed[_tokenIn] && _tokenIn != _tokenOut;
    }

    function getPoolAsset(address _token) external view returns (DataTypes.AssetInfo memory) {
        return _getPoolAsset(_token);
    }

    function getAllTranches() external view returns (address[] memory tranches) {
        uint256 len = allTranches.length;
        tranches = new address[](len);
        for (uint256 i = 0; i < len;) {
            tranches[i] = allTranches[i];
            unchecked {
                ++i;
            }
        }
    }

    function getAllAssets() external view returns (address[] memory assets, bool[] memory isStable) {
        uint256 len = allAssets.length;
        assets = new address[](len);
        isStable = new bool[](len);
        for (uint256 i = 0; i < len;) {
            address token = allAssets[i];
            assets[i] = token;
            isStable[i] = isStableCoin[token];
            unchecked {
                ++i;
            }
        }
    }

    // ============= Mutative functions =============

    function addLiquidity(address _tranche, address _token, uint256 _amountIn, uint256 _minLpAmount, address _to)
        external
        nonReentrant
        onlyListedToken(_token)
    {
        _validateTranche(_tranche);
        if (!isStableCoin[_token] && riskFactor[_token][_tranche] == 0) {
            revert AddLiquidityNotAllowed();
        }
        accrueInterest(_token);
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
        _amountIn = _requireAmount(_getAmountIn(_token));

        (uint256 lpAmount, uint256 feeAmount) = liquidityCalculator.calcAddLiquidity(_tranche, _token, _amountIn);
        if (lpAmount < _minLpAmount) {
            revert SlippageExceeded();
        }

        (uint256 daoFee,) = _calcDaoFee(feeAmount);
        feeReserves[_token] += daoFee;
        trancheAssets[_tranche][_token].poolAmount += (_amountIn - daoFee);
        _validateMaxLiquidity(_token);
        refreshVirtualPoolValue();

        ILPToken(_tranche).mint(_to, lpAmount);
        emit LiquidityAdded(_tranche, msg.sender, _token, _amountIn, lpAmount, daoFee);
    }

    function removeLiquidity(address _tranche, address _tokenOut, uint256 _lpAmount, uint256 _minOut, address _to)
        external
        nonReentrant
        onlyAsset(_tokenOut)
    {
        _validateTranche(_tranche);
        accrueInterest(_tokenOut);
        _requireAmount(_lpAmount);
        ILPToken lpToken = ILPToken(_tranche);

        (uint256 outAmountAfterFee, uint256 feeAmount) =
            liquidityCalculator.calcRemoveLiquidity(_tranche, _tokenOut, _lpAmount);
        if (outAmountAfterFee < _minOut) {
            revert SlippageExceeded();
        }

        (uint256 daoFee,) = _calcDaoFee(feeAmount);
        feeReserves[_tokenOut] += daoFee;
        _decreaseTranchePoolAmount(_tranche, _tokenOut, outAmountAfterFee + daoFee);
        refreshVirtualPoolValue();

        lpToken.burnFrom(msg.sender, _lpAmount);
        _doTransferOut(_tokenOut, _to, outAmountAfterFee);

        emit LiquidityRemoved(_tranche, msg.sender, _tokenOut, _lpAmount, outAmountAfterFee, daoFee);
    }

    function swap(address _tokenIn, address _tokenOut, uint256 _minOut, address _to, bytes calldata extradata)
        external
        nonReentrant
    {
        if (!canSwap(_tokenIn, _tokenOut)) {
            revert InvalidSwapPair();
        }
        accrueInterest(_tokenIn);
        accrueInterest(_tokenOut);
        uint256 amountIn = _requireAmount(_getAmountIn(_tokenIn));
        (uint256 amountOutAfterFee, uint256 swapFee, uint256 priceIn, uint256 priceOut) =
            liquidityCalculator.calcSwapOutput(_tokenIn, _tokenOut, amountIn);
        if (amountOutAfterFee < _minOut) {
            revert SlippageExceeded();
        }
        (uint256 _daoFee,) = _calcDaoFee(swapFee);
        feeReserves[_tokenIn] += _daoFee;
        _rebalanceTranches(_tokenIn, amountIn - _daoFee, _tokenOut, amountOutAfterFee);
        _validateMaxLiquidity(_tokenIn);
        _doTransferOut(_tokenOut, _to, amountOutAfterFee);
        emit Swap(msg.sender, _tokenIn, _tokenOut, amountIn, amountOutAfterFee, swapFee, priceIn, priceOut);
        if (address(poolHook) != address(0)) {
            poolHook.postSwap(_to, _tokenIn, _tokenOut, abi.encode(amountIn, amountOutAfterFee, swapFee, extradata));
        }
    }

    function increasePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        uint256 _sizeChanged,
        DataTypes.Side _side
    ) external onlyOrderManager {
        _requireValidTokenPair(_indexToken, _collateralToken, _side, true);
        IncreasePositionVars memory vars;
        vars.collateralAmount = _requireAmount(_getAmountIn(_collateralToken));
        uint256 collateralPrice = _getCollateralPrice(_collateralToken, true);
        vars.collateralValueAdded = collateralPrice * vars.collateralAmount;
        uint256 borrowIndex = accrueInterest(_collateralToken);
        bytes32 key = PositionLogic.getPositionKey(_owner, _indexToken, _collateralToken, _side);
        DataTypes.Position memory position = positions[key];
        if (position.size == 0) {
            ++positionRevisions[key];
        }
        vars.indexPrice = _getIndexPrice(_indexToken, _side, true);
        vars.sizeChanged = _sizeChanged;

        // update position
        vars.feeValue = _calcPositionFee(position, vars.sizeChanged, borrowIndex);
        vars.feeAmount = vars.feeValue / collateralPrice;
        (vars.daoFee, vars.totalLpFee) = _calcDaoFee(vars.feeAmount);
        vars.reserveAdded = vars.sizeChanged / collateralPrice;

        position.entryPrice = PositionLogic.calcAveragePrice(
            _side, position.size, position.size + vars.sizeChanged, position.entryPrice, vars.indexPrice, 0
        );
        position.collateralValue =
            MathUtils.zeroCapSub(position.collateralValue + vars.collateralValueAdded, vars.feeValue);
        position.size = position.size + vars.sizeChanged;
        position.borrowIndex = borrowIndex;
        position.reserveAmount += vars.reserveAdded;

        if (vars.sizeChanged != 0 && (position.size > position.collateralValue * maxLeverage)) {
            revert InvalidLeverage();
        }

        _validatePosition(position, _collateralToken, _side, vars.indexPrice);

        // update pool assets
        _reservePoolAsset(key, vars, _indexToken, _collateralToken, _side);
        positions[key] = position;

        emit IncreasePosition(
            key,
            _owner,
            _collateralToken,
            _indexToken,
            vars.collateralValueAdded,
            vars.sizeChanged,
            _side,
            vars.indexPrice,
            vars.feeValue
        );

        emit UpdatePosition(
            key,
            position.size,
            position.collateralValue,
            position.entryPrice,
            position.borrowIndex,
            position.reserveAmount,
            vars.indexPrice
        );

        if (address(poolHook) != address(0)) {
            poolHook.postIncreasePosition(
                _owner,
                _indexToken,
                _collateralToken,
                _side,
                abi.encode(_sizeChanged, vars.collateralValueAdded, vars.feeValue)
            );
        }
    }

    function decreasePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        uint256 _collateralChanged,
        uint256 _sizeChanged,
        DataTypes.Side _side,
        address _receiver
    ) external onlyOrderManager {
        _requireValidTokenPair(_indexToken, _collateralToken, _side, false);
        uint256 borrowIndex = accrueInterest(_collateralToken);
        bytes32 key = PositionLogic.getPositionKey(_owner, _indexToken, _collateralToken, _side);
        DataTypes.Position memory position = positions[key];

        if (position.size == 0) {
            revert PositionNotExists();
        }

        DecreasePositionVars memory vars =
            _calcDecreasePayout(position, _indexToken, _collateralToken, _side, _sizeChanged, _collateralChanged, false);

        // reset to actual reduced value instead of user input
        vars.collateralReduced = position.collateralValue - vars.remainingCollateral;
        _releasePoolAsset(key, vars, _indexToken, _collateralToken, _side);
        position.size = position.size - vars.sizeChanged;
        position.borrowIndex = borrowIndex;
        position.reserveAmount = position.reserveAmount - vars.reserveReduced;
        position.collateralValue = vars.remainingCollateral;

        _validatePosition(position, _collateralToken, _side, vars.indexPrice);

        emit DecreasePosition(
            key,
            _owner,
            _collateralToken,
            _indexToken,
            vars.collateralReduced,
            vars.sizeChanged,
            _side,
            vars.indexPrice,
            vars.pnl,
            vars.feeValue
        );
        if (position.size == 0) {
            emit ClosePosition(
                key,
                position.size,
                position.collateralValue,
                position.entryPrice,
                position.borrowIndex,
                position.reserveAmount
            );
            // delete position when closed
            delete positions[key];
        } else {
            emit UpdatePosition(
                key,
                position.size,
                position.collateralValue,
                position.entryPrice,
                position.borrowIndex,
                position.reserveAmount,
                vars.indexPrice
            );
            positions[key] = position;
        }
        _doTransferOut(_collateralToken, _receiver, vars.payout);

        if (address(poolHook) != address(0)) {
            poolHook.postDecreasePosition(
                _owner,
                _indexToken,
                _collateralToken,
                _side,
                abi.encode(vars.sizeChanged, vars.collateralReduced, vars.feeValue)
            );
        }
    }

    function liquidatePosition(address _account, address _indexToken, address _collateralToken, DataTypes.Side _side)
        external
    {
        _requireValidTokenPair(_indexToken, _collateralToken, _side, false);
        uint256 borrowIndex = accrueInterest(_collateralToken);

        bytes32 key = PositionLogic.getPositionKey(_account, _indexToken, _collateralToken, _side);
        DataTypes.Position memory position = positions[key];
        uint256 markPrice = _getIndexPrice(_indexToken, _side, false);
        if (!_liquidatePositionAllowed(position, _side, markPrice, borrowIndex)) {
            revert PositionNotLiquidated();
        }

        DecreasePositionVars memory vars = _calcDecreasePayout(
            position, _indexToken, _collateralToken, _side, position.size, position.collateralValue, true
        );

        _releasePoolAsset(key, vars, _indexToken, _collateralToken, _side);

        emit LiquidatePosition(
            key,
            _account,
            _collateralToken,
            _indexToken,
            _side,
            position.size,
            position.collateralValue - vars.remainingCollateral,
            position.reserveAmount,
            vars.indexPrice,
            vars.pnl,
            vars.feeValue
        );

        delete positions[key];
        _doTransferOut(_collateralToken, _account, vars.payout);
        _doTransferOut(_collateralToken, msg.sender, liquidationFee / vars.collateralPrice);

        if (address(poolHook) != address(0)) {
            poolHook.postLiquidatePosition(
                _account,
                _indexToken,
                _collateralToken,
                _side,
                abi.encode(position.size, position.collateralValue, vars.feeValue)
            );
        }
    }

    function refreshVirtualPoolValue() public {
        virtualPoolValue =
            MathUtils.average(liquidityCalculator.getPoolValue(true), liquidityCalculator.getPoolValue(false));
        emit VirtualPoolValueRefreshed(virtualPoolValue);
    }

    // ========= ADMIN FUNCTIONS ========
    function setInterestRateModel(address _token, address _interestRateModel)
        external
        onlyOwner
        onlyAsset(_token)
    {
        _requireAddress(_interestRateModel);
        interestRateModel[_token] = IInterestRateModel(_interestRateModel);
        emit InterestRateModelSet(_token, _interestRateModel);
    }

    function addTranche(address _tranche) external onlyOwner {
        if (allTranches.length >= Constants.MAX_TRANCHES) {
            revert MaxNumberOfTranchesReached();
        }
        _requireAddress(_tranche);
        if (isTranche[_tranche]) {
            revert TrancheAlreadyAdded();
        }
        isTranche[_tranche] = true;
        allTranches.push(_tranche);
        emit TrancheAdded(_tranche);
    }

    function setOrderManager(address _orderManager) external onlyOwner {
        _requireAddress(_orderManager);
        orderManager = _orderManager;
        emit SetOrderManager(_orderManager);
    }

    function setOracle(address _oracle) external onlyOwner {
        _requireAddress(_oracle);
        address oldOracle = address(oracle);
        oracle = ILevelOracle(_oracle);
        emit OracleChanged(oldOracle, _oracle);
    }

    function setRiskFactor(address _token, RiskConfig[] memory _config) external onlyOwner onlyAsset(_token) {
        if (isStableCoin[_token]) {
            revert NotApplicableForStableCoin();
        }
        uint256 total = totalRiskFactor[_token];
        for (uint256 i = 0; i < _config.length; ++i) {
            (address tranche, uint256 factor) = (_config[i].tranche, _config[i].riskFactor);
            if (!isTranche[tranche]) {
                revert InvalidTranche();
            }
            total = total + factor - riskFactor[_token][tranche];
            riskFactor[_token][tranche] = factor;
        }
        totalRiskFactor[_token] = total;
        emit TokenRiskFactorUpdated(_token);
    }

    function addToken(address _token, bool _isStableCoin) external onlyOwner {
        if (!isAsset[_token]) {
            isAsset[_token] = true;
            isListed[_token] = true;
            allAssets.push(_token);
            isStableCoin[_token] = _isStableCoin;
            if (allAssets.length > Constants.MAX_ASSETS) {
                revert TooManyTokenAdded();
            }
            emit TokenWhitelisted(_token);
            return;
        }

        if (isListed[_token]) {
            revert DuplicateToken();
        }

        // token is added but not listed
        isListed[_token] = true;
        emit TokenWhitelisted(_token);
    }

    function delistToken(address _token) external onlyOwner {
        if (!isListed[_token]) {
            revert AssetNotListed();
        }
        isListed[_token] = false;
        uint256 weight = targetWeights[_token];
        totalWeight -= weight;
        targetWeights[_token] = 0;
        emit TokenDelisted(_token);
    }

    function setMaxLeverage(uint256 _maxLeverage) external onlyOwner {
        _setMaxLeverage(_maxLeverage);
    }

    function setController(address _controller) external onlyOwner {
        _requireAddress(_controller);
        controller = _controller;
        emit PoolControllerChanged(_controller);
    }

    function setMaxLiquidity(address _asset, uint256 _value) external onlyController onlyAsset(_asset) {
        maxLiquidity[_asset] = _value;
        emit MaxLiquiditySet(_asset, _value);
    }

    function setLiquidityCalculator(address _liquidityManager) external onlyOwner {
        _requireAddress(_liquidityManager);
        liquidityCalculator = ILiquidityCalculator(_liquidityManager);
        emit LiquidityCalculatorSet(_liquidityManager);
    }

    function setPositionFee(uint256 _positionFee, uint256 _liquidationFee) external onlyOwner {
        _validateMaxValue(_positionFee, Constants.MAX_POSITION_FEE);
        _validateMaxValue(_liquidationFee, Constants.MAX_LIQUIDATION_FEE);

        positionFee = _positionFee;
        liquidationFee = _liquidationFee;

        emit PositionFeeSet(_positionFee, _liquidationFee);
    }

    function setDaoFee(uint256 _daoFee) external onlyOwner {
        _validateMaxValue(_daoFee, Constants.PRECISION);
        daoFee = _daoFee;
        emit DaoFeeSet(_daoFee);
    }

    function withdrawFee(address _token, address _recipient) external onlyAsset(_token) {
        if (msg.sender != feeDistributor) {
            revert FeeDistributorOnly();
        }
        uint256 amount = feeReserves[_token];
        feeReserves[_token] = 0;
        _doTransferOut(_token, _recipient, amount);
        emit DaoFeeWithdrawn(_token, _recipient, amount);
    }

    function setPositionFeeDistributor(address _feeDistributor) external onlyOwner {
        _requireAddress(_feeDistributor);
        feeDistributor = _feeDistributor;
        emit FeeDistributorSet(feeDistributor);
    }

    function setTargetWeight(TokenWeight[] memory tokens) external onlyController {
        uint256 nTokens = tokens.length;
        if (nTokens != allAssets.length) {
            revert RequireAllTokens();
        }
        uint256 total;
        for (uint256 i = 0; i < nTokens; ++i) {
            TokenWeight memory item = tokens[i];
            assert(isAsset[item.token]);
            // unlisted token always has zero weight
            uint256 weight = isListed[item.token] ? item.weight : 0;
            targetWeights[item.token] = weight;
            total += weight;
        }
        totalWeight = total;
        emit TokenWeightSet(tokens);
    }

    function setPoolHook(address _hook) external onlyOwner {
        poolHook = IPoolHook(_hook);
        emit PoolHookChanged(_hook);
    }

    function setMaxGlobalPositionSize(address _token, uint256 _maxGlobalLongRatio, uint256 _maxGlobalShortSize)
        external
        onlyController
        onlyAsset(_token)
    {
        if (isStableCoin[_token]) {
            revert NotApplicableForStableCoin();
        }

        _validateMaxValue(_maxGlobalLongRatio, Constants.PRECISION);
        maxGlobalLongSizeRatios[_token] = _maxGlobalLongRatio;
        maxGlobalShortSizes[_token] = _maxGlobalShortSize;
        emit MaxGlobalPositionSizeSet(_token, _maxGlobalLongRatio, _maxGlobalShortSize);
    }

    /// @notice move assets between tranches without breaking constrants. Called by controller in rebalance process
    /// to mitigate tranche LP exposure
    function rebalanceAsset(
        address _fromTranche,
        address _fromToken,
        uint256 _fromAmount,
        address _toTranche,
        address _toToken
    ) external onlyController {
        uint256 toAmount = MathUtils.frac(_fromAmount, _getPrice(_fromToken, true), _getPrice(_toToken, true));
        _decreaseTranchePoolAmount(_fromTranche, _fromToken, _fromAmount);
        _decreaseTranchePoolAmount(_toTranche, _toToken, toAmount);
        trancheAssets[_fromTranche][_toToken].poolAmount += toAmount;
        trancheAssets[_toTranche][_fromToken].poolAmount += _fromAmount;
        emit AssetRebalanced();
    }

    // ======== internal functions =========
    function _setMaxLeverage(uint256 _maxLeverage) internal {
        if (_maxLeverage == 0) {
            revert InvalidMaxLeverage();
        }
        maxLeverage = _maxLeverage;
        emit MaxLeverageChanged(_maxLeverage);
    }

    function _setMaintenanceMargin(uint256 _ratio) internal {
        _validateMaxValue(_ratio, Constants.MAX_MAINTENANCE_MARGIN);
        maintenanceMargin = _ratio;
        emit MaintenanceMarginChanged(_ratio);
    }

    function _isValidLeverageTokenPair(
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side,
        bool _isIncrease
    ) internal view returns (bool) {
        if (!isAsset[_indexToken] || !isAsset[_collateralToken]) {
            return false;
        }

        if (_isIncrease && (!isListed[_indexToken] || !isListed[_collateralToken])) {
            return false;
        }

        return _side == DataTypes.Side.LONG ? _indexToken == _collateralToken : isStableCoin[_collateralToken];
    }

    function _validatePosition(
        DataTypes.Position memory _position,
        address _collateralToken,
        DataTypes.Side _side,
        uint256 _indexPrice
    ) internal view {
        if (_position.size != 0 && _position.collateralValue == 0) {
            revert InvalidPositionSize();
        }

        if (_position.size < _position.collateralValue) {
            revert InvalidLeverage();
        }

        uint256 borrowIndex = borrowIndices[_collateralToken];
        if (_liquidatePositionAllowed(_position, _side, _indexPrice, borrowIndex)) {
            revert UpdateCauseLiquidation();
        }
    }

    function _requireValidTokenPair(
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side,
        bool _isIncrease
    ) internal view {
        if (!_isValidLeverageTokenPair(_indexToken, _collateralToken, _side, _isIncrease)) {
            revert InvalidLeverageTokenPair();
        }
    }

    function _validateAsset(address _token) internal view {
        if (!isAsset[_token]) {
            revert UnknownToken();
        }
    }

    function _validateTranche(address _tranche) internal view {
        if (!isTranche[_tranche]) {
            revert InvalidTranche();
        }
    }

    function _requireAddress(address _address) internal pure {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
    }

    function _onlyController() internal view {
        require(msg.sender == controller || msg.sender == owner(), "onlyController");
    }

    function _requireAmount(uint256 _amount) internal pure returns (uint256) {
        if (_amount == 0) {
            revert ZeroAmount();
        }

        return _amount;
    }

    function _requireListedToken(address _token) internal view {
        if (!isListed[_token]) {
            revert AssetNotListed();
        }
    }

    function _requireOrderManager() internal view {
        if (msg.sender != orderManager) {
            revert OrderManagerOnly();
        }
    }

    function _validateMaxValue(uint256 _input, uint256 _max) internal pure {
        if (_input > _max) {
            revert ValueTooHigh();
        }
    }

    function _getAmountIn(address _token) internal returns (uint256 amount) {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        amount = balance - poolBalances[_token];
        poolBalances[_token] = balance;
    }

    function _doTransferOut(address _token, address _to, uint256 _amount) internal {
        if (_amount != 0) {
            IERC20 token = IERC20(_token);
            token.safeTransfer(_to, _amount);
            poolBalances[_token] = token.balanceOf(address(this));
        }
    }

    function accrueInterest(address _token) public returns (uint256) {
        uint256 _now = block.timestamp;
        uint256 lastAccrualTimestamp = lastAccrualTimestamps[_token];
        uint256 borrowIndex = borrowIndices[_token];

        if (lastAccrualTimestamp == 0) {
            lastAccrualTimestamp = (_now / accrualInterval) * accrualInterval;
        } else {
            uint256 nInterval = (_now - lastAccrualTimestamp) / accrualInterval;
            borrowIndex += nInterval * interestRate(_token);
            lastAccrualTimestamp += nInterval * accrualInterval;
        }

        borrowIndices[_token] = borrowIndex;
        lastAccrualTimestamps[_token] = lastAccrualTimestamp;
        emit InterestAccrued(_token, borrowIndex);
        return borrowIndex;
    }

    function interestRate(address _token) public view returns (uint256) {
        uint256 poolAmount;
        uint256 reservedAmount;
        for (uint256 i = 0; i < allTranches.length;) {
            address tranche = allTranches[i];
            poolAmount += trancheAssets[tranche][_token].poolAmount;
            reservedAmount += trancheAssets[tranche][_token].reservedAmount;
            unchecked {
                ++i;
            }
        }

        if (poolAmount == 0 || reservedAmount == 0) {
            return 0;
        }

        return interestRateModel[_token].getBorrowRatePerInterval(poolAmount, reservedAmount);
    }

    function _decreaseTranchePoolAmount(address _tranche, address _token, uint256 _amount) internal {
        DataTypes.AssetInfo memory asset = trancheAssets[_tranche][_token];
        asset.poolAmount -= _amount;
        if (asset.poolAmount < asset.reservedAmount) {
            revert InsufficientPoolAmount();
        }
        trancheAssets[_tranche][_token] = asset;
    }

    /// @notice return pseudo pool asset by sum all tranches asset
    function _getPoolAsset(address _token) internal view returns (DataTypes.AssetInfo memory asset) {
        for (uint256 i = 0; i < allTranches.length;) {
            address tranche = allTranches[i];
            asset.poolAmount += trancheAssets[tranche][_token].poolAmount;
            asset.reservedAmount += trancheAssets[tranche][_token].reservedAmount;
            asset.totalShortSize += trancheAssets[tranche][_token].totalShortSize;
            asset.guaranteedValue += trancheAssets[tranche][_token].guaranteedValue;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice reserve asset when open/increase position
    function _reservePoolAsset(
        bytes32 _key,
        IncreasePositionVars memory _vars,
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side
    ) internal {
        feeReserves[_collateralToken] += _vars.daoFee;

        uint256[] memory shares;
        uint256 totalShare;
        if (_vars.sizeChanged > 0) {
            totalShare = _vars.reserveAdded;
            shares = _calcIncreaseTranchesReserve(_indexToken, _collateralToken, totalShare);
        } else {
            totalShare = _vars.collateralAmount;
            shares = _calcReduceTranchesPoolAmount(_indexToken, _collateralToken, totalShare);
        }

        for (uint256 i = 0; i < shares.length;) {
            address tranche = allTranches[i];
            uint256 share = shares[i];
            DataTypes.AssetInfo memory collateral = trancheAssets[tranche][_collateralToken];

            uint256 reserveAmount = MathUtils.frac(_vars.reserveAdded, share, totalShare);
            tranchePositionReserves[tranche][_key] += reserveAmount;
            collateral.reservedAmount += reserveAmount;
            collateral.poolAmount +=
                MathUtils.frac(_vars.totalLpFee, riskFactor[_indexToken][tranche], totalRiskFactor[_indexToken]);

            if (_side == DataTypes.Side.LONG) {
                collateral.poolAmount = MathUtils.addThenSubWithFraction(
                    collateral.poolAmount, _vars.collateralAmount, _vars.feeAmount, share, totalShare
                );
                // ajust guaranteed
                // guaranteed value = total(size - (collateral - fee))
                // delta_guaranteed value = sizechange + fee - collateral
                collateral.guaranteedValue = MathUtils.addThenSubWithFraction(
                    collateral.guaranteedValue,
                    _vars.sizeChanged + _vars.feeValue,
                    _vars.collateralValueAdded,
                    share,
                    totalShare
                );
            } else {
                uint256 sizeChanged = MathUtils.frac(_vars.sizeChanged, share, totalShare);
                uint256 indexPrice = _vars.indexPrice;

                _updateGlobalShortPosition(tranche, _indexToken, sizeChanged, true, indexPrice, 0);
            }

            trancheAssets[tranche][_collateralToken] = collateral;
            unchecked {
                ++i;
            }
        }

        if (_side == DataTypes.Side.SHORT) {
            _validateGlobalShortSize(_indexToken);
        }
    }

    /// @notice release asset and take or distribute realized PnL when close position
    function _releasePoolAsset(
        bytes32 _key,
        DecreasePositionVars memory _vars,
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side
    ) internal {
        feeReserves[_collateralToken] += _vars.daoFee;

        uint256 totalShare = positions[_key].reserveAmount;

        for (uint256 i = 0; i < allTranches.length;) {
            address tranche = allTranches[i];
            uint256 share = tranchePositionReserves[tranche][_key];
            DataTypes.AssetInfo memory collateral = trancheAssets[tranche][_collateralToken];

            {
                uint256 reserveReduced = MathUtils.frac(_vars.reserveReduced, share, totalShare);
                tranchePositionReserves[tranche][_key] -= reserveReduced;
                collateral.reservedAmount -= reserveReduced;
            }

            uint256 lpFee =
                MathUtils.frac(_vars.totalLpFee, riskFactor[_indexToken][tranche], totalRiskFactor[_indexToken]);
            collateral.poolAmount = (
                (collateral.poolAmount + lpFee).toInt256() - _vars.poolAmountReduced.frac(share, totalShare)
            ).toUint256();

            if (collateral.poolAmount < collateral.reservedAmount) {
                revert InsufficientPoolAmount();
            }

            int256 pnl = _vars.pnl.frac(share, totalShare);
            if (_side == DataTypes.Side.LONG) {
                collateral.guaranteedValue = MathUtils.addThenSubWithFraction(
                    collateral.guaranteedValue, _vars.collateralReduced, _vars.sizeChanged, share, totalShare
                );
            } else {
                uint256 sizeChanged = MathUtils.frac(_vars.sizeChanged, share, totalShare);
                uint256 indexPrice = _vars.indexPrice;
                _updateGlobalShortPosition(tranche, _indexToken, sizeChanged, false, indexPrice, pnl);
            }
            trancheAssets[tranche][_collateralToken] = collateral;
            emit PnLDistributed(_collateralToken, tranche, pnl);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * INCREASE POSTION:
     * - size change => distribute reserve amount to tranches, should cap to utilization threshold
     * - size not change => distribute collateral to tranches
     * SWAP: distribute amount out to tranches, should cap to pool amount
     */

    /**
     * @notice calculate reserve amount added to tranche when increase position size
     */
    function _calcIncreaseTranchesReserve(address _indexToken, address _collateralToken, uint256 _reserveAmount)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 nTranches = allTranches.length;
        uint256[] memory factors = new uint256[](nTranches);
        uint256 totalFactor = totalRiskFactor[_indexToken];
        uint256[] memory maxShare = new uint256[](nTranches);
        bool isLong = _indexToken == _collateralToken;
        uint256 maxLongRatio = maxGlobalLongSizeRatios[_indexToken];

        for (uint256 i = 0; i < nTranches;) {
            address tranche = allTranches[i];
            DataTypes.AssetInfo memory asset = trancheAssets[tranche][_collateralToken];
            factors[i] = riskFactor[_indexToken][tranche];
            maxShare[i] = isLong && maxLongRatio != 0
                ? MathUtils.zeroCapSub(asset.poolAmount * maxLongRatio / Constants.PRECISION, asset.reservedAmount)
                : asset.poolAmount - asset.reservedAmount;
            unchecked {
                ++i;
            }
        }

        return _calcDistribution(_reserveAmount, factors, totalFactor, maxShare);
    }

    /**
     * @notice calculate pool amount to remove from tranche when increase position collateral or swap in
     */
    function _calcReduceTranchesPoolAmount(address _indexToken, address _collateralToken, uint256 _amount)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 nTranches = allTranches.length;
        uint256[] memory factors = new uint256[](nTranches);
        uint256 totalFactor = isStableCoin[_indexToken] ? nTranches : totalRiskFactor[_indexToken];
        uint256[] memory maxShare = new uint256[](nTranches);

        for (uint256 i = 0; i < nTranches;) {
            address tranche = allTranches[i];
            DataTypes.AssetInfo memory asset = trancheAssets[tranche][_collateralToken];
            factors[i] = isStableCoin[_indexToken] ? 1 : riskFactor[_indexToken][tranche];
            maxShare[i] = asset.poolAmount - asset.reservedAmount;
            unchecked {
                ++i;
            }
        }

        return _calcDistribution(_amount, factors, totalFactor, maxShare);
    }

    function _calcDistribution(uint256 _amount, uint256[] memory _weights, uint256 _totalWeight, uint256[] memory _cap)
        internal
        pure
        returns (uint256[] memory distribution)
    {
        uint256 nTranches = _weights.length;
        distribution = new uint[](nTranches);
        for (uint256 k = 0; k < nTranches;) {
            unchecked {
                ++k;
            }
            uint256 denom = _totalWeight;
            for (uint256 i = 0; i < nTranches;) {
                uint256 numerator = _weights[i];
                if (numerator != 0) {
                    uint256 share = MathUtils.frac(_amount, numerator, denom);
                    uint256 available = _cap[i] - distribution[i];
                    if (share >= available) {
                        // skip this tranche on next rounds since it's full
                        share = available;
                        _totalWeight -= numerator;
                        _weights[i] = 0;
                    }

                    distribution[i] += share;
                    _amount -= share;
                    denom -= numerator;
                    if (_amount == 0) {
                        return distribution;
                    }
                }
                unchecked {
                    ++i;
                }
            }
        }

        revert CannotDistributeToTranches();
    }

    /// @notice rebalance fund between tranches after swap token
    function _rebalanceTranches(address _tokenIn, uint256 _amountIn, address _tokenOut, uint256 _amountOut) internal {
        // amount devided to each tranche
        uint256[] memory outAmounts = _calcReduceTranchesPoolAmount(_tokenIn, _tokenOut, _amountOut);

        for (uint256 i = 0; i < outAmounts.length;) {
            address tranche = allTranches[i];
            trancheAssets[tranche][_tokenOut].poolAmount -= outAmounts[i];
            trancheAssets[tranche][_tokenIn].poolAmount += MathUtils.frac(_amountIn, outAmounts[i], _amountOut);
            unchecked {
                ++i;
            }
        }
    }

    function _liquidatePositionAllowed(
        DataTypes.Position memory _position,
        DataTypes.Side _side,
        uint256 _indexPrice,
        uint256 _borrowIndex
    ) internal view returns (bool allowed) {
        if (_position.size == 0) {
            return false;
        }
        // calculate fee needed when close position
        uint256 feeValue = _calcPositionFee(_position, _position.size, _borrowIndex);
        int256 pnl = PositionLogic.calcPnl(_side, _position.size, _position.entryPrice, _indexPrice);
        int256 collateral = pnl + _position.collateralValue.toInt256();

        // liquidation occur when collateral cannot cover margin fee or lower than maintenance margin
        return collateral < 0 || uint256(collateral) * Constants.PRECISION < _position.size * maintenanceMargin
            || uint256(collateral) < (feeValue + liquidationFee);
    }

    function _calcDecreasePayout(
        DataTypes.Position memory _position,
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side,
        uint256 _sizeChanged,
        uint256 _collateralChanged,
        bool isLiquidate
    ) internal view returns (DecreasePositionVars memory vars) {
        // clean user input
        vars.sizeChanged = MathUtils.min(_position.size, _sizeChanged);
        vars.collateralReduced = _position.collateralValue < _collateralChanged || _position.size == vars.sizeChanged
            ? _position.collateralValue
            : _collateralChanged;

        vars.indexPrice = _getIndexPrice(_indexToken, _side, false);
        vars.collateralPrice = _getCollateralPrice(_collateralToken, false);

        // vars is santinized, only trust these value from now on
        vars.reserveReduced = (_position.reserveAmount * vars.sizeChanged) / _position.size;
        vars.pnl = PositionLogic.calcPnl(_side, vars.sizeChanged, _position.entryPrice, vars.indexPrice);
        vars.feeValue = _calcPositionFee(_position, vars.sizeChanged, borrowIndices[_collateralToken]);

        // first try to deduct fee and lost (if any) from withdrawn collateral
        int256 payoutValue = vars.pnl + vars.collateralReduced.toInt256() - vars.feeValue.toInt256();
        if (isLiquidate) {
            payoutValue = payoutValue - liquidationFee.toInt256();
        }
        int256 remainingCollateral = (_position.collateralValue - vars.collateralReduced).toInt256(); // subtraction never overflow, checked above
        // if the deduction is too much, try to deduct from remaining collateral
        if (payoutValue < 0) {
            remainingCollateral = remainingCollateral + payoutValue;
            payoutValue = 0;
        }
        vars.payout = uint256(payoutValue) / vars.collateralPrice;

        int256 poolValueReduced = vars.pnl;
        if (remainingCollateral < 0) {
            if (!isLiquidate) {
                revert UpdateCauseLiquidation();
            }
            // if liquidate too slow, pool must take the lost
            poolValueReduced = poolValueReduced - remainingCollateral;
            vars.remainingCollateral = 0;
        } else {
            vars.remainingCollateral = uint256(remainingCollateral);
        }

        if (_side == DataTypes.Side.LONG) {
            poolValueReduced = poolValueReduced + vars.collateralReduced.toInt256();
        } else if (poolValueReduced < 0) {
            // in case of SHORT, trader can lost unlimited value but pool can only increase at most collateralValue - liquidationFee
            poolValueReduced = poolValueReduced.lowerCap(
                MathUtils.zeroCapSub(_position.collateralValue, vars.feeValue + liquidationFee)
            );
        }
        vars.poolAmountReduced = poolValueReduced / vars.collateralPrice.toInt256();
        (vars.daoFee, vars.totalLpFee) = _calcDaoFee(vars.feeValue / vars.collateralPrice);
    }

    function _calcPositionFee(DataTypes.Position memory _position, uint256 _sizeChanged, uint256 _borrowIndex)
        internal
        view
        returns (uint256 feeValue)
    {
        uint256 borrowFee = ((_borrowIndex - _position.borrowIndex) * _position.size) / Constants.PRECISION;
        uint256 _positionFee = (_sizeChanged * positionFee) / Constants.PRECISION;
        feeValue = borrowFee + _positionFee;
    }

    function _getIndexPrice(address _token, DataTypes.Side _side, bool _isIncrease) internal view returns (uint256) {
        // max == (_isIncrease & _side = LONG) | (!_increase & _side = SHORT)
        // max = _isIncrease == (_side == DataTypes.Side.LONG);
        return _getPrice(_token, _isIncrease == (_side == DataTypes.Side.LONG));
    }

    function _getCollateralPrice(address _token, bool _isIncrease) internal view returns (uint256) {
        return (isStableCoin[_token])
            // force collateral price = 1 incase of using stablecoin as collateral
            ? 10 ** (USD_VALUE_DECIMAL - IERC20Metadata(_token).decimals())
            : _getPrice(_token, !_isIncrease);
    }

    function _getPrice(address _token, bool _max) internal view returns (uint256) {
        return oracle.getPrice(_token, _max);
    }

    function _validateMaxLiquidity(address _token) internal view {
        uint256 max = maxLiquidity[_token];
        if (max == 0) {
            return;
        }

        if (_getPoolAsset(_token).poolAmount > max) {
            revert MaxLiquidityReach();
        }
    }

    function _updateGlobalShortPosition(
        address _tranche,
        address _indexToken,
        uint256 _sizeChanged,
        bool _isIncrease,
        uint256 _indexPrice,
        int256 _realizedPnl
    ) internal {
        uint256 lastSize = trancheAssets[_tranche][_indexToken].totalShortSize;
        uint256 nextSize = _isIncrease ? lastSize + _sizeChanged : MathUtils.zeroCapSub(lastSize, _sizeChanged);
        uint256 entryPrice = trancheAssets[_tranche][_indexToken].averageShortPrice;
        trancheAssets[_tranche][_indexToken].averageShortPrice = PositionLogic.calcAveragePrice(
            DataTypes.Side.SHORT, lastSize, nextSize, entryPrice, _indexPrice, _realizedPnl
        );
        trancheAssets[_tranche][_indexToken].totalShortSize = nextSize;
        globalShortSize = globalShortSize - lastSize + nextSize;
    }

    function _validateGlobalShortSize(address _indexToken) internal view {
        uint256 maxGlobalShortSize = maxGlobalShortSizes[_indexToken];
        if (maxGlobalShortSize != 0 && maxGlobalShortSize < globalShortSize) {
            revert MaxGlobalShortSizeExceeded();
        }
    }

    function _calcDaoFee(uint256 _feeAmount) internal view returns (uint256 _daoFee, uint256 lpFee) {
        _daoFee = MathUtils.frac(_feeAmount, daoFee, Constants.PRECISION);
        lpFee = _feeAmount - _daoFee;
    }
}

