// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ====================== BaseOrchestrator ======================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {Auth, Authority} from "./Auth.sol";

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Address} from "./Address.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {OrchestratorHelper, Keys} from "./OrchestratorHelper.sol";

import {IWETH} from "./IWETH.sol";
import {IBaseOrchestratorSetter} from "./IBaseOrchestratorSetter.sol";
import {IBaseOrchestratorReader} from "./IBaseOrchestratorReader.sol";

import {IBaseRouteFactory} from "./IBaseRouteFactory.sol";
import {IBaseOrchestrator, IBaseRoute} from "./IBaseOrchestrator.sol";

/// @title BaseOrchestrator
/// @notice This abstract contract contains the logic for managing Routes and Puppets
abstract contract BaseOrchestrator is IBaseOrchestrator, Auth, ReentrancyGuard {

    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public constant MAX_FEE = 1000; // 10% max fee

    bool private _initialized;

    IBaseOrchestratorReader public immutable reader;
    IBaseOrchestratorSetter public immutable setter;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _authority The Authority contract instance
    /// @param _reader The Reader contract address
    /// @param _setter The Setter contract address
    constructor(Authority _authority, address _reader, address _setter) Auth(address(0), _authority) {
        reader = IBaseOrchestratorReader(_reader);
        setter = IBaseOrchestratorSetter(_setter);
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Modifier that ensures the caller is a route
    modifier onlyRoute() {
        OrchestratorHelper.isRouteRegistered(reader, msg.sender);
        _;
    }

    /// @notice Modifier that ensures the contract is not paused
    modifier notPaused() {
        OrchestratorHelper.isPaused(reader);
        _;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    /// @inheritdoc IBaseOrchestrator
    function getPrice(address _token) virtual external view returns (uint256);

    // ============================================================================================
    // Trader Function
    // ============================================================================================

    /// @inheritdoc IBaseOrchestrator
    // slither-disable-next-line reentrancy-no-eth
    function registerRouteAccount(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bytes memory _data
    ) public nonReentrant notPaused returns (bytes32) {
        (
            address _route,
            bytes32 _routeKey,
            bytes32 _routeTypeKey
        ) = OrchestratorHelper.registerRouteAccount(
            reader,
            setter,
            msg.sender,
            _collateralToken,
            _indexToken,
            _isLong,
            _data
        );

        emit RegisterRouteAccount(msg.sender, _route, _routeTypeKey);

        return _routeKey;
    }

    /// @inheritdoc IBaseOrchestrator
    function requestPosition(
        IBaseRoute.AdjustPositionParams memory _adjustPositionParams,
        IBaseRoute.SwapParams memory _swapParams,
        bytes32 _routeTypeKey,
        uint256 _executionFee,
        bool _isIncrease
    ) public payable nonReentrant notPaused returns (bytes32 _requestKey) {
        bytes32 _routeKey = reader.routeKey(msg.sender, _routeTypeKey);
        address _route = OrchestratorHelper.validateRouteKey(reader, _routeKey);

        OrchestratorHelper.removeExpiredSubscriptions(reader, setter, _routeKey);

        if (_isIncrease && (msg.value == _executionFee)) {
            address _token = _swapParams.path[0];
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _swapParams.amount);
        }

        _requestKey = IBaseRoute(_route).requestPosition{ value: msg.value }(
            _adjustPositionParams,
            _swapParams,
            _executionFee,
            _isIncrease
        );

        if (reader.isPositionOpen(_routeKey)) {
            emit AdjustPosition(msg.sender, _route, _isIncrease, _requestKey, _routeTypeKey, _getPositionKey(_route));
        } else {
            emit OpenPosition(
                reader.subscribedPuppets(_routeKey),
                msg.sender,
                _route,
                _isIncrease,
                _requestKey, 
                _routeTypeKey,
                _getPositionKey(_route)
            );
        }
    }

    /// @inheritdoc IBaseOrchestrator
    function registerRouteAccountAndRequestPosition(
        IBaseRoute.AdjustPositionParams memory _adjustPositionParams,
        IBaseRoute.SwapParams memory _swapParams,
        uint256 _executionFee,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bytes memory _data
    ) external payable returns (bytes32 _routeKey, bytes32 _requestKey) {
        _routeKey = registerRouteAccount(_collateralToken, _indexToken, _isLong, _data);

        _requestKey = requestPosition(
            _adjustPositionParams,
            _swapParams,
            Keys.routeTypeKey(_collateralToken, _indexToken, _isLong, _data),
            _executionFee,
            true
        );
    }

    // ============================================================================================
    // Puppet Functions
    // ============================================================================================

    /// @inheritdoc IBaseOrchestrator
    function subscribeRoute(
        uint256 _allowance,
        uint256 _expiry,
        address _puppet,
        address _trader,
        bytes32 _routeTypeKey, 
        bool _subscribe
    ) public nonReentrant notPaused {
        if (msg.sender != reader.multiSubscriber()) _puppet = msg.sender;

        address _route = OrchestratorHelper.subscribePuppet(
            reader,
            setter,
            _expiry,
            _allowance,
            _trader,
            _puppet,
            _routeTypeKey,
            _subscribe
        );

        emit SubscribeRoute(_allowance, _expiry, _trader, _puppet, _route, _routeTypeKey, _subscribe);
    }

    /// @inheritdoc IBaseOrchestrator
    function batchSubscribeRoute(
        address _owner,
        uint256[] memory _allowances,
        uint256[] memory _expiries,
        address[] memory _traders,
        bytes32[] memory _routeTypeKeys,
        bool[] memory _subscribe
    ) public {
        if (_traders.length != _allowances.length) revert MismatchedInputArrays();
        if (_traders.length != _expiries.length) revert MismatchedInputArrays();
        if (_traders.length != _subscribe.length) revert MismatchedInputArrays();
        if (_traders.length != _routeTypeKeys.length) revert MismatchedInputArrays();

        for (uint256 i = 0; i < _traders.length; i++) {
            subscribeRoute(_allowances[i], _expiries[i], _owner, _traders[i], _routeTypeKeys[i], _subscribe[i]);
        }
    }

    /// @inheritdoc IBaseOrchestrator
    function deposit(uint256 _amount, address _asset, address _puppet) public payable nonReentrant notPaused {
        OrchestratorHelper.validatePuppetInput(reader, _amount, _puppet, _asset);

        if (msg.value > 0) {
            if (_amount != msg.value) revert InvalidAmount();
            if (_asset != reader.wnt()) revert InvalidAsset();
        }

        _creditPuppetAccount(_amount, _asset, msg.sender);

        if (msg.value > 0) {
            payable(_asset).functionCallWithValue(abi.encodeWithSignature("deposit()"), _amount);
        } else {
            IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        }

        emit Deposit(_amount, _asset, msg.sender, _puppet);
    }

    /// @inheritdoc IBaseOrchestrator
    function depositAndBatchSubscribe(
        uint256 _amount,
        address _asset,
        address _owner,
        uint256[] memory _allowances,
        uint256[] memory _expiries,
        address[] memory _traders,
        bytes32[] memory _routeTypeKeys,
        bool[] memory _subscribe
    ) external payable {
        deposit(_amount, _asset, _owner);

        batchSubscribeRoute(_owner, _allowances, _expiries, _traders, _routeTypeKeys, _subscribe);
    }

    /// @inheritdoc IBaseOrchestrator
    function withdraw(uint256 _amount, address _asset, address _receiver, bool _isETH) external nonReentrant {
        OrchestratorHelper.validatePuppetInput(reader, _amount, _receiver, _asset);

        if (_isETH && _asset != reader.wnt()) revert InvalidAsset();
 
        _debitPuppetAccount(_amount, _asset, msg.sender, true);

        if (_isETH) {
            IWETH(_asset).withdraw(_amount);
            payable(_receiver).sendValue(_amount);
        } else {
            IERC20(_asset).safeTransfer(_receiver, _amount);
        }

        emit Withdraw(_amount, _asset, _receiver, msg.sender);
    }

    /// @inheritdoc IBaseOrchestrator
    function setThrottleLimit(uint256 _throttleLimit, bytes32 _routeType) external nonReentrant notPaused {
        setter.updateThrottleLimit(_throttleLimit, msg.sender, _routeType);

        emit SetThrottleLimit(msg.sender, _routeType, _throttleLimit);
    }

    // ============================================================================================
    // Route Functions
    // ============================================================================================

    /// @inheritdoc IBaseOrchestrator
    function debitPuppetAccount(uint256[] memory _amounts, address[] memory _puppets, address _asset) external onlyRoute {
        for (uint256 i = 0; i < _puppets.length; i++) {
            _debitPuppetAccount(_amounts[i], _asset, _puppets[i], false);
        }
    } 

    /// @inheritdoc IBaseOrchestrator
    function creditPuppetAccount(uint256[] memory _amounts, address[] memory _puppets, address _asset) external onlyRoute {
        for (uint256 i = 0; i < _puppets.length; i++) {
            _creditPuppetAccount(_amounts[i], _asset, _puppets[i]);
        }
    }

    /// @inheritdoc IBaseOrchestrator
    function updateLastPositionOpenedTimestamp(address[] memory _puppets) external onlyRoute {
        bytes32 _routeType = OrchestratorHelper.updateLastPositionOpenedTimestamp(
            reader,
            setter,
            msg.sender,
            _puppets
        );

        emit UpdateOpenTimestamp(_puppets, _routeType);
    }

    /// @inheritdoc IBaseOrchestrator
    function transferRouteFunds(uint256 _amount, address _asset, address _receiver) external onlyRoute {
        IERC20(_asset).safeTransfer(_receiver, _amount);

        emit TransferRouteFunds(_amount, _asset, _receiver, msg.sender);
    }

    /// @inheritdoc IBaseOrchestrator
    function emitExecutionCallback(uint256 _performanceFeePaid, bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external onlyRoute {
        emit ExecutePosition(_performanceFeePaid, msg.sender, _requestKey, _isExecuted, _isIncrease);
    }

    /// @inheritdoc IBaseOrchestrator
    function emitSharesIncrease(uint256[] memory _puppetsShares, uint256 _traderShares, uint256 _totalSupply) external onlyRoute {
        emit SharesIncrease(_puppetsShares, _traderShares, _totalSupply, _getPositionKey(msg.sender));
    }

    // ============================================================================================
    // Authority Functions
    // ============================================================================================

    // called by keeper

    /// @inheritdoc IBaseOrchestrator
    function adjustTargetLeverage(
        IBaseRoute.AdjustPositionParams memory _adjustPositionParams,
        uint256 _executionFee,
        bytes32 _routeKey
    ) external payable requiresAuth nonReentrant returns (bytes32 _requestKey) {
        address _route = OrchestratorHelper.validateRouteKey(reader, _routeKey);

        _requestKey = IBaseRoute(_route).decreaseSize{ value: msg.value }(_adjustPositionParams, _executionFee);

        emit AdjustTargetLeverage(_route, _requestKey, _routeKey, _getPositionKey(_route));
    }

    /// @inheritdoc IBaseOrchestrator
    function liquidatePosition(bytes32 _routeKey) external requiresAuth nonReentrant {
        address _route = OrchestratorHelper.validateRouteKey(reader, _routeKey);

        IBaseRoute(_route).liquidate();

        emit LiquidatePosition(_route, _routeKey, _getPositionKey(_route));
    }

    // called by owner

    /// @inheritdoc IBaseOrchestrator
    function initialize(
        address _keeper,
        address _platformFeeRecipient,
        address _routeFactory,
        address _routeSetter,
        address _gauge,
        bytes memory _data
    ) external requiresAuth {
        if (_initialized) revert AlreadyInitialized();
        if (_keeper == address(0)) revert ZeroAddress();
        if (_platformFeeRecipient == address(0)) revert ZeroAddress();
        if (_routeFactory == address(0)) revert ZeroAddress();
        if (_routeSetter == address(0)) revert ZeroAddress();

        _initialized = true;

        setter.setInitializeData(
            _keeper,
            _platformFeeRecipient,
            _routeFactory,
            _gauge,
            address(this),
            _routeSetter
        );

        _initialize(_data);

        emit Initialize(_keeper, _platformFeeRecipient, _routeFactory, _gauge, _routeSetter);
    }

    /// @inheritdoc IBaseOrchestrator
    function withdrawPlatformFees(address _asset) external returns (uint256 _balance) {
        if (_asset == address(0)) revert ZeroAddress();

        _balance = reader.platformAccountBalance(_asset);
        if (_balance == 0) revert ZeroAmount();

        setter.updatePlatformAccountBalance(0, _asset);

        address _platformFeeRecipient = reader.platformFeeRecipient();
        IERC20(_asset).safeTransfer(_platformFeeRecipient, _balance);

        emit WithdrawPlatformFees(_balance, _asset, msg.sender, _platformFeeRecipient);
    }

    /// @inheritdoc IBaseOrchestrator
    function updateRouteFactory(address _routeFactory) external requiresAuth {
        if (_routeFactory == address(0)) revert ZeroAddress();

        setter.updateRouteFactory(_routeFactory);

        emit UpdateRouteFactory(_routeFactory);
    }

    /// @inheritdoc IBaseOrchestrator
    function updateMultiSubscriber(address _multiSubscriber) external requiresAuth {
        if (_multiSubscriber == address(0)) revert ZeroAddress();

        setter.updateMultiSubscriber(_multiSubscriber);

        emit UpdateMultiSubscriber(_multiSubscriber);
    }

    /// @inheritdoc IBaseOrchestrator
    function setRouteType(address _collateralToken, address _indexToken, bool _isLong, bytes memory _data) external requiresAuth {
        bytes32 _routeTypeKey = Keys.routeTypeKey(_collateralToken, _indexToken, _isLong, _data);
        setter.setRouteType(_routeTypeKey, _collateralToken, _indexToken, _isLong);

        emit SetRouteType(_routeTypeKey, _collateralToken, _indexToken, _isLong);
    }

    /// @inheritdoc IBaseOrchestrator
    function updateKeeper(address _keeper) external requiresAuth {
        if (_keeper == address(0)) revert ZeroAddress();

        setter.updateKeeper(_keeper);

        emit UpdateKeeper(_keeper);
    }

    /// @inheritdoc IBaseOrchestrator
    function updateScoreGauge(address _gauge) external requiresAuth {
        if (_gauge == address(0)) revert ZeroAddress();

        setter.updateScoreGauge(_gauge);

        emit UpdateScoreGauge(_gauge);
    }

    /// @inheritdoc IBaseOrchestrator
    function updateReferralCode(bytes32 _referralCode) external requiresAuth {
        if (_referralCode == bytes32(0)) revert ZeroBytes32();

        setter.updateReferralCode(_referralCode);

        emit UpdateReferralCode(_referralCode);
    }

    /// @inheritdoc IBaseOrchestrator
    function updatePlatformFeesRecipient(address _recipient) external requiresAuth {
        if (_recipient == address(0)) revert ZeroAddress();

        setter.updatePlatformFeesRecipient(_recipient);

        emit SetFeesRecipient(_recipient);
    }

    /// @inheritdoc IBaseOrchestrator
    function updatePauseSwitch(bool _paused) external requiresAuth {
        setter.updatePauseSwitch(_paused);

        emit Pause(_paused);
    }

    /// @inheritdoc IBaseOrchestrator
    function setFees(uint256 _managmentFee, uint256 _withdrawalFee, uint256 _performanceFee) external requiresAuth nonReentrant {
        if (_managmentFee > MAX_FEE || _withdrawalFee > MAX_FEE || _performanceFee > MAX_FEE) revert FeeExceedsMax();

        setter.updateFees(_managmentFee, _withdrawalFee, _performanceFee);

        emit SetFees(_managmentFee, _withdrawalFee, _performanceFee);
    }

    /// @inheritdoc IBaseOrchestrator
    function rescueRouteFunds(uint256 _amount, address _token, address _receiver, address _route) external requiresAuth nonReentrant {
        IBaseRoute(_route).rescueTokenFunds(_amount, _token, _receiver);

        emit RescueRouteFunds(_amount, _token, _receiver, _route);
    }

    // ============================================================================================
    // Internal Mutated Functions
    // ============================================================================================

    function _initialize(bytes memory _data) internal virtual {}

    function _debitPuppetAccount(uint256 _amount, address _asset, address _puppet, bool _isWithdraw) internal {
        uint256 _feeAmount = (
            _isWithdraw
            ? (_amount * reader.withdrawalFeePercentage())
            : (_amount * reader.managementFeePercentage())
        ) / reader.basisPointsDivisor();

        setter.debitPuppetAccount(_amount, _feeAmount, _asset, _puppet);

        emit DebitPuppet(_amount, _asset, _puppet, msg.sender);
        emit CreditPlatform(_feeAmount, _asset, _puppet, msg.sender, _isWithdraw);
    }

    function _creditPuppetAccount(uint256 _amount, address _asset, address _puppet) internal {
        setter.creditPuppetAccount(_amount, _asset, _puppet);

        emit CreditPuppet(_amount, _asset, _puppet, msg.sender);
    }

    // ============================================================================================
    // Internal View Functions
    // ============================================================================================

    function _getPositionKey(address _route) internal view returns (bytes32) {
        return reader.positionKey(_route);
    }

    // ============================================================================================
    // Receive Function
    // ============================================================================================

    receive() external payable {}
}
