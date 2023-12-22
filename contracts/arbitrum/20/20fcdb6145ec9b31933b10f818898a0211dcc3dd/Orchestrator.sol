// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================== Orchestrator ========================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {Auth, Authority} from "./Auth.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {EnumerableMap} from "./EnumerableMap.sol";

import {IGMXVaultPriceFeed} from "./IGMXVaultPriceFeed.sol";

import {IRouteFactory} from "./IRouteFactory.sol";

import "./Base.sol";

/// @title Orchestrator
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice This contract contains the logic and storage for managing routes and puppets
contract Orchestrator is Auth, Base, IOrchestrator {

    using SafeERC20 for IERC20;
    using Address for address payable;

    struct RouteInfo {
        address route;
        bool isRegistered;
        EnumerableSet.AddressSet puppets;
        RouteType routeType;
    }

    struct PuppetInfo {
        mapping(bytes32 => uint256) throttleLimits; // routeType => throttle limit (in seconds)
        mapping(bytes32 => uint256) lastPositionOpenedTimestamp; // routeType => timestamp
        mapping(address => uint256) depositAccount; // collateralToken => balance
        EnumerableMap.AddressToUintMap allowances; // route => allowance percentage
    }

    // settings
    address public routeFactory;

    address private _keeper;

    bool private _paused;

    bytes32 private _referralCode;

    GMXInfo private _gmxInfo;

    // routes info
    mapping(address => bool) public isRoute; // Route => isRoute
    mapping(bytes32 => RouteType) public routeType; // routeTypeKey => RouteType

    mapping(bytes32 => RouteInfo) private _routeInfo; // routeKey => RouteInfo

    address[] private _routes;

    // puppets info
    mapping(address => PuppetInfo) private _puppetInfo;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _authority The Authority contract instance
    /// @param _routeFactory The RouteFactory contract address
    /// @param _keeperAddr The address of the keeper
    /// @param _refCode The GMX referral code
    /// @param _gmx The GMX contract addresses
    constructor(
        Authority _authority,
        address _routeFactory,
        address _keeperAddr,
        bytes32 _refCode,
        bytes memory _gmx
    ) Auth(address(0), _authority) {
        routeFactory = _routeFactory;
        _keeper = _keeperAddr;

        (
            _gmxInfo.vaultPriceFeed,
            _gmxInfo.router,
            _gmxInfo.vault,
            _gmxInfo.positionRouter
        ) = abi.decode(_gmx, (address, address, address, address));

        _referralCode = _refCode;
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Modifier that ensures the caller is a route
    modifier onlyRoute() {
        if (!isRoute[msg.sender]) revert NotRoute();
        _;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    /// @inheritdoc IOrchestrator
    function keeper() external view returns (address) {
        return _keeper;
    }

    /// @inheritdoc IOrchestrator
    function referralCode() external view returns (bytes32) {
        return _referralCode;
    }

    /// @inheritdoc IOrchestrator
    function routes() external view returns (address[] memory) {
        return _routes;
    }

    /// @inheritdoc IOrchestrator
    function paused() external view returns (bool) {
        return _paused;
    }

    // route

    /// @inheritdoc IOrchestrator
    function getRouteTypeKey(address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_collateralToken, _indexToken, _isLong));
    }

    /// @inheritdoc IOrchestrator
    function getRouteKey(address _trader, bytes32 _routeTypeKey) public view returns (bytes32) {
        address _collateralToken = routeType[_routeTypeKey].collateralToken;
        address _indexToken = routeType[_routeTypeKey].indexToken;
        bool _isLong = routeType[_routeTypeKey].isLong;

        return keccak256(abi.encodePacked(_trader, _collateralToken, _indexToken, _isLong));
    }

    /// @inheritdoc IOrchestrator
    function getPositionKey(IRoute _route) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(_route), _route.collateralToken(), _route.indexToken(), _route.isLong()));
    }

    /// @inheritdoc IOrchestrator
    function subscribedPuppets(bytes32 _routeKey) public view returns (address[] memory _puppets) {
        EnumerableSet.AddressSet storage _puppetsSet = _routeInfo[_routeKey].puppets;
        _puppets = new address[](EnumerableSet.length(_puppetsSet));

        for (uint256 i = 0; i < EnumerableSet.length(_puppetsSet); i++) {
            _puppets[i] = EnumerableSet.at(_puppetsSet, i);
        }
    }

    /// @inheritdoc IOrchestrator
    function getRoute(bytes32 _routeKey) external view returns (address) {
        return _routeInfo[_routeKey].route;
    }

    /// @inheritdoc IOrchestrator
    function getRoute(address _trader, address _collateralToken, address _indexToken, bool _isLong) external view returns (address) {
        bytes32 _routeTypeKey = getRouteTypeKey(_collateralToken, _indexToken, _isLong);
        bytes32 _routeKey = getRouteKey(_trader, _routeTypeKey);

        return _routeInfo[_routeKey].route;
    }

    // puppet

    /// @inheritdoc IOrchestrator
    function puppetSubscriptions(address _puppet) external view returns (address[] memory _subscriptions) {
        EnumerableMap.AddressToUintMap storage _allowances = _puppetInfo[_puppet].allowances;

        uint256 _subscriptionCount = EnumerableMap.length(_allowances);
        _subscriptions = new address[](_subscriptionCount);
        for (uint256 i = 0; i < _subscriptionCount; i++) {
            (_subscriptions[i],) = EnumerableMap.at(_allowances, i);
        }
    }

    /// @inheritdoc IOrchestrator
    function puppetAllowancePercentage(address _puppet, address _route) external view returns (uint256) {
        return EnumerableMap.get(_puppetInfo[_puppet].allowances, _route);
    }

    /// @inheritdoc IOrchestrator
    function puppetAccountBalance(address _puppet, address _asset) external view returns (uint256) {
        return _puppetInfo[_puppet].depositAccount[_asset];
    }

    /// @inheritdoc IOrchestrator
    function puppetThrottleLimit(address _puppet, bytes32 _routeType) external view returns (uint256) {
        return _puppetInfo[_puppet].throttleLimits[_routeType];
    }

    /// @inheritdoc IOrchestrator
    function lastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external view returns (uint256) {
        return _puppetInfo[_puppet].lastPositionOpenedTimestamp[_routeType];
    }

    /// @inheritdoc IOrchestrator
    function isBelowThrottleLimit(address _puppet, bytes32 _routeType) external view returns (bool) {
        return (block.timestamp - _puppetInfo[_puppet].lastPositionOpenedTimestamp[_routeType]) >= _puppetInfo[_puppet].throttleLimits[_routeType];
    }

    // gmx

    /// @inheritdoc IOrchestrator
    function getPrice(address _token) external view returns (uint256) {
        return IGMXVaultPriceFeed(_gmxInfo.vaultPriceFeed).getPrice(
            _token,
            _gmxInfo.priceFeedMaximise,
            _gmxInfo.priceFeedIncludeAmmPrice,
            false
        );
    }

    /// @inheritdoc IOrchestrator
    function gmxVaultPriceFeed() external view returns (address) {
        return _gmxInfo.vaultPriceFeed;
    }

    /// @inheritdoc IOrchestrator
    function gmxRouter() external view returns (address) {
        return _gmxInfo.router;
    }

    /// @inheritdoc IOrchestrator
    function gmxPositionRouter() external view returns (address) {
        return _gmxInfo.positionRouter;
    }

    /// @inheritdoc IOrchestrator
    function gmxVault() external view returns (address) {
        return _gmxInfo.vault;
    }

    // ============================================================================================
    // Trader Function
    // ============================================================================================

    /// @inheritdoc IOrchestrator
    // slither-disable-next-line reentrancy-no-eth
    function createRoute(address _collateralToken, address _indexToken, bool _isLong) public nonReentrant returns (bytes32 _routeKey) {
        if (_collateralToken == address(0) || _indexToken == address(0)) revert ZeroAddress();

        bytes32 _routeTypeKey = getRouteTypeKey(_collateralToken, _indexToken, _isLong);
        if (!routeType[_routeTypeKey].isRegistered) revert RouteTypeNotRegistered();

        _routeKey = getRouteKey(msg.sender, _routeTypeKey);
        if (_routeInfo[_routeKey].isRegistered) revert RouteAlreadyRegistered();

        address _routeAddr = IRouteFactory(routeFactory).createRoute(address(this), msg.sender, _collateralToken, _indexToken, _isLong);

        RouteType memory _routeType = RouteType({
            collateralToken: _collateralToken,
            indexToken: _indexToken,
            isLong: _isLong,
            isRegistered: true
        });

        RouteInfo storage _route = _routeInfo[_routeKey];

        _route.route = _routeAddr;
        _route.isRegistered = true;
        _route.routeType = _routeType;

        isRoute[_routeAddr] = true;
        _routes.push(_routeAddr);

        emit CreateRoute(msg.sender, _routeAddr, _routeTypeKey);
    }

    /// @inheritdoc IOrchestrator
    function registerRouteAndRequestPosition(
        IRoute.AdjustPositionParams memory _adjustPositionParams,
        IRoute.SwapParams memory _swapParams,
        uint256 _executionFee,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external payable returns (bytes32 _routeKey, bytes32 _requestKey) {
        _routeKey = createRoute(_collateralToken, _indexToken, _isLong);
        _requestKey = requestPosition(
            _adjustPositionParams,
            _swapParams,
            getRouteTypeKey(_collateralToken, _indexToken, _isLong),
            _executionFee,
            true
        );
    }

    /// @inheritdoc IOrchestrator
    function requestPosition(
        IRoute.AdjustPositionParams memory _adjustPositionParams,
        IRoute.SwapParams memory _swapParams,
        bytes32 _routeTypeKey,
        uint256 _executionFee,
        bool _isIncrease
    ) public payable nonReentrant returns (bytes32 _requestKey) {
        bytes32 _routeKey = getRouteKey(msg.sender, _routeTypeKey);
        IRoute _route = IRoute(_routeInfo[_routeKey].route);
        if (address(_route) == address(0)) revert RouteNotRegistered();

        _requestKey = _route.requestPosition{ value: msg.value }(
            _adjustPositionParams,
            _swapParams,
            _executionFee,
            _isIncrease
        );

        address[] memory _puppets = _route.isPositionOpen() ? _route.puppets() : subscribedPuppets(_routeKey);

        emit RequestPosition(_puppets, msg.sender, _routeTypeKey, getPositionKey(_route));
    }

    /// @inheritdoc IOrchestrator
    function approvePlugin(bytes32 _routeTypeKey) external {
        address _route = _routeInfo[getRouteKey(msg.sender, _routeTypeKey)].route;
        if (_route == address(0)) revert RouteNotRegistered();

        IRoute(_route).approvePlugin();

        emit ApprovePlugin(msg.sender, _routeTypeKey);
    }

    // ============================================================================================
    // Puppet Functions
    // ============================================================================================

    /// @inheritdoc IOrchestrator
    function subscribeRoute(uint256 _allowance, address _trader, bytes32 _routeTypeKey, bool _subscribe) public nonReentrant {
        bytes32 _routeKey = getRouteKey(_trader, _routeTypeKey);
        RouteInfo storage _route = _routeInfo[_routeKey];
        PuppetInfo storage _puppet = _puppetInfo[msg.sender];

        if (!_route.isRegistered) revert RouteNotRegistered();
        if (IRoute(_route.route).isWaitingForCallback()) revert RouteWaitingForCallback();

        if (_subscribe) {
            if (_allowance > _BASIS_POINTS_DIVISOR || _allowance == 0) revert InvalidAllowancePercentage();

            EnumerableMap.set(_puppet.allowances, _route.route, _allowance);
            EnumerableSet.add(_route.puppets, msg.sender);
        } else {
            EnumerableMap.remove(_puppet.allowances, _route.route);
            EnumerableSet.remove(_route.puppets, msg.sender);
        }

        emit SubscribeRoute(_allowance, _trader, msg.sender, _routeTypeKey, _subscribe);
    }

    /// @inheritdoc IOrchestrator
    function batchSubscribeRoute(
        uint256[] memory _allowances,
        address[] memory _traders,
        bytes32[] memory _routeTypeKeys,
        bool[] memory _subscribe
    ) external {
        if (_traders.length != _allowances.length) revert MismatchedInputArrays();
        if (_traders.length != _subscribe.length) revert MismatchedInputArrays();
        if (_traders.length != _routeTypeKeys.length) revert MismatchedInputArrays();

        for (uint256 i = 0; i < _traders.length; i++) {
            subscribeRoute(_allowances[i], _traders[i], _routeTypeKeys[i], _subscribe[i]);
        }
    }

    /// @inheritdoc IOrchestrator
    function deposit(uint256 _amount, address _asset, address _puppet) external payable nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        if (_puppet == address(0)) revert ZeroAddress();
        if (_asset == address(0)) revert ZeroAddress();
        if (msg.value > 0) {
            if (_amount != msg.value) revert InvalidAmount();
            if (_asset != _WETH) revert InvalidAsset();
        }

        _puppetInfo[_puppet].depositAccount[_asset] += _amount;

        if (msg.value > 0) {
            payable(_asset).functionCallWithValue(abi.encodeWithSignature("deposit()"), _amount);
        } else {
            IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        }

        emit Deposit(_amount, _asset, msg.sender, _puppet);
    }

    /// @inheritdoc IOrchestrator
    function withdraw(uint256 _amount, address _asset, address _receiver, bool _isETH) external nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        if (_receiver == address(0)) revert ZeroAddress();
        if (_asset == address(0)) revert ZeroAddress();
        if (_isETH && _asset != _WETH) revert InvalidAsset();
 
        _puppetInfo[msg.sender].depositAccount[_asset] -= _amount;

        if (_isETH) {
            IWETH(_asset).withdraw(_amount);
            payable(_receiver).sendValue(_amount);
        } else {
            IERC20(_asset).safeTransfer(_receiver, _amount);
        }

        emit Withdraw(_amount, _asset, _receiver, msg.sender);
    }

    /// @inheritdoc IOrchestrator
    function setThrottleLimit(uint256 _throttleLimit, bytes32 _routeType) external {
        _puppetInfo[msg.sender].throttleLimits[_routeType] = _throttleLimit;

        emit SetThrottleLimit(msg.sender, _routeType, _throttleLimit);
    }

    // ============================================================================================
    // Route Functions
    // ============================================================================================

    /// @inheritdoc IOrchestrator
    function debitPuppetAccount(uint256 _amount, address _asset, address _puppet) external onlyRoute {
        _puppetInfo[_puppet].depositAccount[_asset] -= _amount;

        emit DebitPuppet(_amount, _asset, _puppet, msg.sender);
    }

    /// @inheritdoc IOrchestrator
    function creditPuppetAccount(uint256 _amount, address _asset, address _puppet) external onlyRoute {
        _puppetInfo[_puppet].depositAccount[_asset] += _amount;

        emit CreditPuppet(_amount, _asset, _puppet, msg.sender);
    }

    /// @inheritdoc IOrchestrator
    function updateLastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external onlyRoute {
        _puppetInfo[_puppet].lastPositionOpenedTimestamp[_routeType] = block.timestamp;

        emit UpdateOpenTimestamp(_puppet, _routeType, block.timestamp);
    }

    /// @inheritdoc IOrchestrator
    function transferRouteFunds(uint256 _amount, address _asset, address _receiver) external onlyRoute {
        IERC20(_asset).safeTransfer(_receiver, _amount);

        emit TransferRouteFunds(_amount, _asset, _receiver, msg.sender);
    }

    /// @inheritdoc IOrchestrator
    function emitExecutionCallback(bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external onlyRoute {
        emit ExecutePosition(msg.sender, _requestKey, _isExecuted, _isIncrease);
    }

    /// @inheritdoc IOrchestrator
    function emitSharesIncrease(uint256[] memory _puppetsShares, uint256 _traderShares, uint256 _totalSupply) external onlyRoute {
        emit SharesIncrease(_puppetsShares, _traderShares, _totalSupply, getPositionKey(IRoute(msg.sender)));
    }

    // ============================================================================================
    // Authority Functions
    // ============================================================================================

    // called by keeper

    /// @inheritdoc IOrchestrator
    function adjustTargetLeverage(
        IRoute.AdjustPositionParams memory _adjustPositionParams,
        uint256 _executionFee,
        bytes32 _routeKey
    ) external payable requiresAuth nonReentrant returns (bytes32 _requestKey) {
        IRoute _route = IRoute(_routeInfo[_routeKey].route);
        if (address(_route) == address(0)) revert RouteNotRegistered();

        _requestKey = _route.decreaseSize{ value: msg.value }(_adjustPositionParams, _executionFee);

        emit AdjustTargetLeverage(_requestKey, _routeKey, getPositionKey(_route));
    }

    /// @inheritdoc IOrchestrator
    function liquidatePosition(bytes32 _routeKey) external requiresAuth nonReentrant {
        IRoute _route = IRoute(_routeInfo[_routeKey].route);
        if (address(_route) == address(0)) revert RouteNotRegistered();


        _route.liquidate();

        emit LiquidatePosition(_routeKey, getPositionKey(_route));
    }

    // called by owner

    /// @inheritdoc IOrchestrator
    function rescueTokens(uint256 _amount, address _token, address _receiver) external requiresAuth nonReentrant {
        if (_token == address(0)) {
            payable(_receiver).sendValue(_amount);
        } else {
            IERC20(_token).safeTransfer(_receiver, _amount);
        }

        emit Rescue(_amount, _token, _receiver);
    }

    /// @inheritdoc IOrchestrator
    function rescueRouteFunds(uint256 _amount, address _token, address _receiver, address _route) external requiresAuth nonReentrant {
        IRoute(_route).rescueTokenFunds(_amount, _token, _receiver);

        emit RescueRouteFunds(_amount, _token, _receiver, _route);
    }

    /// @inheritdoc IOrchestrator
    function freezeRoute(address _route, bool _freeze) external requiresAuth nonReentrant {
        IRoute(_route).freeze(_freeze);

        emit FreezeRoute(_route, _freeze);
    }

    /// @inheritdoc IOrchestrator
    function setRouteType(address _collateral, address _index, bool _isLong) external requiresAuth nonReentrant {
        bytes32 _routeTypeKey = getRouteTypeKey(_collateral, _index, _isLong);
        routeType[_routeTypeKey] = RouteType(_collateral, _index, _isLong, true);

        emit SetRouteType(_routeTypeKey, _collateral, _index, _isLong);
    }

    /// @inheritdoc IOrchestrator
    function setGMXInfo(
        address _vaultPriceFeed,
        address _router,
        address _vault,
        address _positionRouter,
        bool _priceFeedMaximise,
        bool _priceFeedIncludeAmmPrice
    ) external requiresAuth nonReentrant {
        GMXInfo storage _gmx = _gmxInfo;

        _gmx.vaultPriceFeed = _vaultPriceFeed;
        _gmx.router = _router;
        _gmx.vault = _vault;
        _gmx.positionRouter = _positionRouter;
        _gmx.priceFeedMaximise = _priceFeedMaximise;
        _gmx.priceFeedIncludeAmmPrice = _priceFeedIncludeAmmPrice;

        emit SetGMXUtils(_vaultPriceFeed, _router, _vault, _positionRouter, _priceFeedMaximise, _priceFeedIncludeAmmPrice);
    }

    /// @inheritdoc IOrchestrator
    function setKeeper(address _keeperAddr) external requiresAuth nonReentrant {
        if (_keeperAddr == address(0)) revert ZeroAddress();

        _keeper = _keeperAddr;

        emit SetKeeper(_keeper);
    }

    /// @inheritdoc IOrchestrator
    function setReferralCode(bytes32 _refCode) external requiresAuth nonReentrant {
        if (_refCode == bytes32(0)) revert ZeroBytes32();

        _referralCode = _refCode;

        emit SetReferralCode(_refCode);
    }

    /// @inheritdoc IOrchestrator
    function setRouteFactory(address _factory) external requiresAuth nonReentrant {
        if (_factory == address(0)) revert ZeroAddress();

        routeFactory = _factory;

        emit SetRouteFactory(_factory);
    }

    /// @inheritdoc IOrchestrator
    function pause(bool _pause) external requiresAuth nonReentrant {
        _paused = _pause;

        emit Pause(_pause);
    }

    // ============================================================================================
    // Receive Function
    // ============================================================================================

    receive() external payable {}
}
