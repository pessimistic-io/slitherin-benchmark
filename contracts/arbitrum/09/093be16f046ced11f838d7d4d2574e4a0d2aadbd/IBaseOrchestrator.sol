// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ====================== IBaseOrchestrator =====================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IBaseRoute} from "./IBaseRoute.sol";

interface IBaseOrchestrator {

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    /// @notice The ```getPrice``` function returns the price for a given Token from the GMX vaultPriceFeed
    /// @notice prices are USD denominated with 30 decimals
    /// @param _token The address of the Token
    /// @return _price The price
    function getPrice(address _token) external view returns (uint256 _price);

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // Trader

    /// @notice The ```registerRouteAccount``` function is called by a Trader to register a new Route Account
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @param _data Any additional data
    /// @return bytes32 The Route key
    function registerRouteAccount(address _collateralToken, address _indexToken, bool _isLong, bytes memory _data) external returns (bytes32);

    /// @notice The ```requestPosition``` function creates a new position request
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _routeTypeKey The RouteType key
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @param _isIncrease The boolean indicating if the request is an increase or decrease request
    /// @return _requestKey The request key
    function requestPosition(IBaseRoute.AdjustPositionParams memory _adjustPositionParams, IBaseRoute.SwapParams memory _swapParams, bytes32 _routeTypeKey, uint256 _executionFee, bool _isIncrease) external payable returns (bytes32 _requestKey);

    /// @notice The ```registerRouteAccountAndRequestPosition``` function is called by a Trader to register a new Route Account and create an Increase Position Request
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @param _data Any additional data
    /// @return _routeKey The Route key
    /// @return _requestKey The request key
    function registerRouteAccountAndRequestPosition(IBaseRoute.AdjustPositionParams memory _adjustPositionParams, IBaseRoute.SwapParams memory _swapParams, uint256 _executionFee, address _collateralToken, address _indexToken, bool _isLong, bytes memory _data) external payable returns (bytes32 _routeKey, bytes32 _requestKey);

    // Puppet

    /// @notice The ```subscribeRoute``` function is called by a Puppet to update his subscription to a Route
    /// @param _allowance The allowance percentage
    /// @param _subscriptionPeriod The subscription period
    /// @param _puppet The subscribing Puppet
    /// @param _trader The address of the Trader
    /// @param _routeTypeKey The RouteType key
    /// @param _subscribe Whether to subscribe or unsubscribe
    function subscribeRoute(uint256 _allowance, uint256 _subscriptionPeriod, address _puppet, address _trader, bytes32 _routeTypeKey, bool _subscribe) external;

    /// @notice The ```batchSubscribeRoute``` function is called by a Puppet to update his subscription to a list of Routes
    /// @param _owner The subscribing Puppet
    /// @param _allowances The allowance percentage array
    /// @param _subscriptionPeriods The subscription period array
    /// @param _traders The address array of Traders
    /// @param _routeTypeKeys The RouteType key array
    /// @param _subscribe Whether to subscribe or unsubscribe
    function batchSubscribeRoute(address _owner, uint256[] memory _allowances, uint256[] memory _subscriptionPeriods, address[] memory _traders, bytes32[] memory _routeTypeKeys, bool[] memory _subscribe) external;

    /// @notice The ```deposit``` function is called by a Puppet to deposit funds into his deposit account
    /// @param _amount The amount to deposit
    /// @param _asset The address of the Asset
    /// @param _puppet The address of the recepient
    function deposit(uint256 _amount, address _asset, address _puppet) external payable;

    /// @notice The ```depositAndBatchSubscribe``` function is called by a Puppet to deposit funds into his deposit account and update his subscription to a list of Routes
    /// @param _amount The amount to deposit
    /// @param _asset The address of the Asset
    /// @param _owner The subscribing Puppet
    /// @param _allowances The allowance percentage array
    /// @param _expiries The subscription period array
    /// @param _traders The address array of Traders
    /// @param _routeTypeKeys The RouteType key array
    /// @param _subscribe Whether to subscribe or unsubscribe
    function depositAndBatchSubscribe(uint256 _amount, address _asset, address _owner, uint256[] memory _allowances, uint256[] memory _expiries, address[] memory _traders, bytes32[] memory _routeTypeKeys, bool[] memory _subscribe) external payable;

    /// @notice The ```withdraw``` function is called by a Puppet to withdraw funds from his deposit account
    /// @param _amount The amount to withdraw
    /// @param _asset The address of the Asset
    /// @param _receiver The address of the receiver of withdrawn funds
    /// @param _isETH Whether to withdraw ETH or not. Available only for WETH deposits
    function withdraw(uint256 _amount, address _asset, address _receiver, bool _isETH) external;

    /// @notice The ```setThrottleLimit``` function is called by a Puppet to set his throttle limit for a given RouteType
    /// @param _throttleLimit The throttle limit
    /// @param _routeType The RouteType key
    function setThrottleLimit(uint256 _throttleLimit, bytes32 _routeType) external;

    // Route

    /// @notice The ```debitPuppetAccount``` function is called by a Route to debit a Puppet's account
    /// @param _amounts The uint256 array of amounts to debit
    /// @param _puppets The address array of the Puppets to debit
    /// @param _asset The address of the Asset
    function debitPuppetAccount(uint256[] memory _amounts, address[] memory _puppets, address _asset) external;

    /// @notice The ```creditPuppetAccount``` function is called by a Route to credit a Puppet's account
    /// @param _amounts The uint256 array of amounts to credit
    /// @param _puppets The address array of the Puppets to credit
    /// @param _asset The address of the Asset
    function creditPuppetAccount(uint256[] memory _amounts, address[] memory _puppets, address _asset) external;

    /// @notice The ```updateLastPositionOpenedTimestamp``` function is called by a Route to update the last position opened timestamp of a Puppet
    /// @param _puppets The address array of the Puppets
    function updateLastPositionOpenedTimestamp(address[] memory _puppets) external;

    /// @notice The ```transferRouteFunds``` function is called by a Route to send funds to a _receiver
    /// @param _amount The amount to send
    /// @param _asset The address of the Asset
    /// @param _receiver The address of the receiver
    function transferRouteFunds(uint256 _amount, address _asset, address _receiver) external;

    /// @notice The ```emitExecutionCallback``` function is called by a Route to emit an event on a GMX position execution callback
    /// @param performanceFeePaid The performance fee paid to Trader
    /// @param _requestKey The request key
    /// @param _isExecuted The boolean indicating if the request is executed
    /// @param _isIncrease The boolean indicating if the request is an increase or decrease request
    function emitExecutionCallback(uint256 performanceFeePaid, bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external;

    /// @notice The ```emitSharesIncrease``` function is called by a Route to emit an event on a successful add collateral request
    /// @param _puppetsShares The array of Puppets shares, corresponding to the Route's subscribed Puppets, as stored in the Route Position struct
    /// @param _traderShares The Trader's shares, as stored in the Route Position struct
    /// @param _totalSupply The total supply of the Route's shares
    function emitSharesIncrease(uint256[] memory _puppetsShares, uint256 _traderShares, uint256 _totalSupply) external;

    // Authority

    // called by keeper

    /// @notice The ```adjustTargetLeverage``` function is called by a keeper to adjust mirrored position to target leverage to match trader leverage
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _executionFee The total execution fee, paid by the Keeper in ETH
    /// @param _routeKey The Route key
    /// @return _requestKey The request key
    function adjustTargetLeverage(IBaseRoute.AdjustPositionParams memory _adjustPositionParams, uint256 _executionFee, bytes32 _routeKey) external payable returns (bytes32 _requestKey);

    /// @notice The ```liquidatePosition``` function is called by Puppet keepers to reset the Route's accounting in case of a liquidation
    /// @param _routeKey The Route key
    function liquidatePosition(bytes32 _routeKey) external;

    // called by owner

    /// @notice The ```initialize``` function is called by the Authority to initialize the contract
    /// @dev Function is callable only once and execution is paused until then
    /// @param _keeper The address of the Keeper
    /// @param _platformFeeRecipient The address of the platform fees recipient
    /// @param _routeFactory The address of the RouteFactory
    /// @param _routeSetter The address of the RouteSetter
    /// @param _gauge The address of the Score Gauge
    /// @param _data The bytes of any additional data
    function initialize(address _keeper, address _platformFeeRecipient, address _routeFactory, address _routeSetter, address _gauge, bytes memory _data) external;

    /// @notice The ```withdrawPlatformFees``` function is called by anyone to withdraw platform fees
    /// @param _asset The address of the Asset
    /// @return _amount The amount withdrawn
    function withdrawPlatformFees(address _asset) external returns (uint256 _amount);

    /// @notice The ```updateRouteFactory``` function is called by the Authority to set the RouteFactory address
    /// @param _routeFactory The address of the new RouteFactory
    function updateRouteFactory(address _routeFactory) external;

    /// @notice The ```updateMultiSubscriber``` function is called by the Authority to set the MultiSubscriber address
    /// @param _multiSubscriber The address of the new MultiSubscriber
    function updateMultiSubscriber(address _multiSubscriber) external;

    /// @notice The ```setRouteType``` function is called by the Authority to set a new RouteType
    /// @dev system doesn't support tokens that apply a fee/burn/rebase on transfer 
    /// @param _collateral The address of the Collateral Token
    /// @param _index The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @param _data Any additional data
    function setRouteType(address _collateral, address _index, bool _isLong, bytes memory _data) external;

    /// @notice The ```updateKeeper``` function is called by the Authority to set the Keeper address
    /// @param _keeperAddr The address of the new Keeper
    function updateKeeper(address _keeperAddr) external;

    /// @notice The ```updateScoreGauge``` function is called by the Authority to set the Score Gauge address
    /// @param _gauge The address of the new Score Gauge
    function updateScoreGauge(address _gauge) external;

    /// @notice The ```updateReferralCode``` function is called by the Authority to set the referral code
    /// @param _refCode The new referral code
    function updateReferralCode(bytes32 _refCode) external;

    /// @notice The ```updatePlatformFeesRecipient``` function is called by the Authority to set the platform fees recipient
    /// @param _recipient The new platform fees recipient
    function updatePlatformFeesRecipient(address _recipient) external;

    /// @notice The ```setPause``` function is called by the Authority to pause all Routes
    /// @param _pause The new pause state
    function updatePauseSwitch(bool _pause) external;

    /// @notice The ```setFees``` function is called by the Authority to set the management and withdrawal fees
    /// @param _managmentFee The new management fee
    /// @param _withdrawalFee The new withdrawal fee
    /// @param _performanceFee The new performance fee
    function setFees(uint256 _managmentFee, uint256 _withdrawalFee, uint256 _performanceFee) external;

    /// @notice The ```rescueRouteFunds``` function is called by the Authority to rescue tokens from a Route
    /// @dev Route should never hold any funds, but this function is here just in case
    /// @param _amount The amount to rescue
    /// @param _token The address of the Token
    /// @param _receiver The address of the receiver
    /// @param _route The address of the Route
    function rescueRouteFunds(uint256 _amount, address _token, address _receiver, address _route) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event RegisterRouteAccount(address indexed trader, address indexed route, bytes32 routeTypeKey);

    event SubscribeRoute(uint256 allowance, uint256 subscriptionExpiry, address indexed trader, address indexed puppet, address indexed route, bytes32 routeTypeKey, bool subscribe);
    event SetThrottleLimit(address indexed puppet, bytes32 routeType, uint256 throttleLimit);

    event UpdateOpenTimestamp(address[] indexed puppets, bytes32 routeType);
    
    event Deposit(uint256 amount, address asset, address caller, address indexed puppet);
    event Withdraw(uint256 amount, address asset, address indexed receiver, address indexed puppet);

    event AdjustPosition(address indexed trader, address indexed route, bool isIncrease, bytes32 requestKey, bytes32 routeTypeKey, bytes32 positionKey); 
    event OpenPosition(address[] puppets, address indexed trader, address indexed route, bool isIncrease, bytes32 requestKey, bytes32 routeTypeKey, bytes32 positionKey);
    event ExecutePosition(uint256 performanceFeePaid, address indexed route, bytes32 requestKey, bool isExecuted, bool isIncrease);
    event SharesIncrease(uint256[] puppetsShares, uint256 traderShares, uint256 totalSupply, bytes32 positionKey);
    event AdjustTargetLeverage(address indexed route, bytes32 requestKey, bytes32 routeKey, bytes32 positionKey);
    event LiquidatePosition(address indexed route, bytes32 routeKey, bytes32 positionKey);

    event DebitPuppet(uint256 amount, address asset, address indexed puppet, address indexed caller);
    event CreditPlatform(uint256 amount, address asset, address puppet, address caller, bool isWithdraw);
    event CreditPuppet(uint256 amount, address asset, address indexed puppet, address indexed caller);

    event TransferRouteFunds(uint256 amount, address asset, address indexed receiver, address indexed caller);
    event Initialize(address keeper, address platformFeeRecipient, address routeFactory, address gauge, address routeSetter);
    event WithdrawPlatformFees(uint256 amount, address asset, address caller, address platformFeeRecipient);

    event UpdateRouteFactory(address routeFactory);
    event UpdateMultiSubscriber(address multiSubscriber);
    event SetRouteType(bytes32 routeTypeKey, address collateral, address index, bool isLong);
    event UpdateKeeper(address keeper);
    event UpdateScoreGauge(address scoreGauge);
    event UpdateReferralCode(bytes32 referralCode);
    event SetFeesRecipient(address recipient);
    event Pause(bool paused);
    event SetFees(uint256 managmentFee, uint256 withdrawalFee, uint256 performanceFee);
    event RescueRouteFunds(uint256 amount, address token, address indexed receiver, address indexed route);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error MismatchedInputArrays();
    error RouteNotRegistered();
    error InvalidAmount();
    error InvalidAsset();
    error ZeroAddress();
    error ZeroBytes32();
    error ZeroAmount();
    error FunctionCallPastDeadline();
    error NotWhitelisted();
    error FeeExceedsMax();
    error AlreadyInitialized();
}
