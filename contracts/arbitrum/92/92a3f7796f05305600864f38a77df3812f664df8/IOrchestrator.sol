// SPDX-License-Identifier: AGPL
pragma solidity 0.8.17;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================== IOrchestrator =======================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/Puppet

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IRoute} from "./IRoute.sol";

interface IOrchestrator {

    struct RouteType {
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isRegistered;
    }

    struct GMXInfo {
        address gmxRouter;
        address gmxVault;
        address gmxPositionRouter;
        address gmxReferralRebatesSender;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    /// @notice The ```keeper``` function returns the address of the Keeper
    /// @return address The address of the Keeper
    function keeper() external view returns (address);

    /// @notice The ```referralCode``` function returns the referral code
    /// @return bytes32 The referral code
    function referralCode() external view returns (bytes32);

    /// @notice The ```routes``` function returns all the routes
    /// @return address The address array of all the routes
    function routes() external view returns (address[] memory);

    /// @notice The ```paused``` function returns the paused state
    /// @return bool The paused state
    function paused() external view returns (bool);

    // route

    /// @notice The ```getRouteTypeKey``` function returns RouteType key for a given Route attributes
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @return bytes32 The RouteType key
    function getRouteTypeKey(address _collateralToken, address _indexToken, bool _isLong) external pure returns (bytes32);

    /// @notice The ```getRouteKey``` function returns the Route key for a given RouteType key and Trader address
    /// @param _trader The address of the Trader
    /// @param _routeTypeKey The RouteType key
    /// @return bytes32 The Route key
    function getRouteKey(address _trader, bytes32 _routeTypeKey) external view returns (bytes32);

    /// @notice The ```getRoute``` function returns the Route address for a given Route key
    /// @param _routeKey The Route key
    /// @return address The Route address
    function getRoute(bytes32 _routeKey) external view returns (address);

    /// @notice The ```getRoute``` function returns the Route address for a given Route attributes and Trader address
    /// @param _trader The address of the Trader
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @return address The Route address
    function getRoute(address _trader, address _collateralToken, address _indexToken, bool _isLong) external view returns (address);

    /// @notice The ```subscribedPuppets``` function returns all the subscribed puppets for a given Route key
    /// @notice Those puppets may not be subscribed to the current Route's position
    /// @param _routeKey The Route key
    /// @return _puppets The address array of all the subscribed puppets
    function subscribedPuppets(bytes32 _routeKey) external view returns (address[] memory _puppets);

    // puppet

    /// @notice The ```puppetSubscriptions``` function returns all the subscriptions for a given Puppet
    /// @param _puppet The address of the Puppet
    /// @return _subscriptions The address array of all the routes that the Puppet is subscribed to
    function puppetSubscriptions(address _puppet) external view returns (address[] memory _subscriptions);

    /// @notice The ```puppetAllowancePercentage``` function returns the allowance percentage for a given Puppet and Route
    /// @param _puppet The address of the Puppet
    /// @param _route The address of the Route
    /// @return _allowance The allowance percentage
    function puppetAllowancePercentage(address _puppet, address _route) external view returns (uint256 _allowance);

    /// @notice The ```puppetAccountBalance``` function returns the account balance for a given Puppet and Asset
    /// @param _puppet The address of the Puppet
    /// @param _asset The address of the Asset
    /// @return uint256 The account balance
    function puppetAccountBalance(address _puppet, address _asset) external view returns (uint256);

    /// @notice The ```puppetThrottleLimit``` function returns the throttle limit for a given Puppet and RouteType
    /// @param _puppet The address of the Puppet
    /// @param _routeType The RouteType key
    /// @return uint256 The throttle limit
    function puppetThrottleLimit(address _puppet, bytes32 _routeType) external view returns (uint256);

    /// @notice The ```lastPositionOpenedTimestamp``` function returns the last position opened timestamp for a given Puppet and RouteType
    /// @param _puppet The address of the Puppet
    /// @param _routeType The RouteType key
    /// @return uint256 The last position opened timestamp
    function lastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external view returns (uint256);

    /// @notice The ```isBelowThrottleLimit``` function returns whether a given Puppet is below the throttle limit for a given RouteType
    /// @param _puppet The address of the Puppet
    /// @param _routeType The RouteType key
    /// @return bool Whether the Puppet is below the throttle limit
    function isBelowThrottleLimit(address _puppet, bytes32 _routeType) external view returns (bool);

    // gmx

    /// @notice The ```gmxInfo``` function returns the GMX Router address
    /// @return address The GMX Router address
    function gmxRouter() external view returns (address);

    /// @notice The ```gmxPositionRouter``` function returns the GMX Position Router address
    /// @return address The GMX Position Router address
    function gmxPositionRouter() external view returns (address);

    /// @notice The ```gmxVault``` function returns the GMX Vault address
    /// @return address The GMX Vault address
    function gmxVault() external view returns (address);

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // Trader

    /// @notice The ```registerRoute``` function is called by a Trader to register a new Route
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @return bytes32 The Route key
    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external returns (bytes32);

    /// @notice The ```registerRouteAndRequestPosition``` function is called by a Trader to register a new Route and create an Increase Position Request
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    function registerRouteAndRequestPosition(IRoute.AdjustPositionParams memory _adjustPositionParams, IRoute.SwapParams memory _swapParams, uint256 _executionFee, address _collateralToken, address _indexToken, bool _isLong) external payable returns (bytes32 _routeKey, bytes32 _requestKey);

    /// @notice The ```requestPosition``` function creates a new position request
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _routeTypeKey The RouteType key
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @param _isIncrease The boolean indicating if the request is an increase or decrease request
    /// @return _requestKey The request key
    function requestPosition(IRoute.AdjustPositionParams memory _adjustPositionParams, IRoute.SwapParams memory _swapParams, bytes32 _routeTypeKey, uint256 _executionFee, bool _isIncrease) external payable returns (bytes32 _requestKey);

    /// @notice The ```approvePlugin``` function is used to approve the GMX plugin in case we change the gmxPositionRouter address
    /// @param _routeTypeKey The RouteType key
    function approvePlugin(bytes32 _routeTypeKey) external;

    // Puppet

    /// @notice The ```deposit``` function is called by a Puppet to deposit funds into his deposit account
    /// @param _amount The amount to deposit
    /// @param _asset The address of the Asset
    /// @param _puppet The address of the recepient
    function deposit(uint256 _amount, address _asset, address _puppet) external payable;

    /// @notice The ```withdraw``` function is called by a Puppet to withdraw funds from his deposit account
    /// @param _amount The amount to withdraw
    /// @param _asset The address of the Asset
    /// @param _receiver The address of the receiver of withdrawn funds
    /// @param _isETH Whether to withdraw ETH or not. Available only for WETH deposits
    function withdraw(uint256 _amount, address _asset, address _receiver, bool _isETH) external;

    /// @notice The ```updateRoutesSubscription``` function is called by a Puppet to update his subscription to a list of Routes
    /// @param _traders The address array of Traders
    /// @param _allowances The corresponding allowance percentage array
    /// @param _routeTypeKey The RouteType key
    /// @param _subscribe Whether to subscribe or unsubscribe
    function updateRoutesSubscription(address[] memory _traders, uint256[] memory _allowances, bytes32 _routeTypeKey, bool _subscribe) external;

    /// @notice The ```setThrottleLimit``` function is called by a Puppet to set his throttle limit for a given RouteType
    /// @param _throttleLimit The throttle limit
    /// @param _routeType The RouteType key
    function setThrottleLimit(uint256 _throttleLimit, bytes32 _routeType) external;

    // Route

    /// @notice The ```debitPuppetAccount``` function is called by a Route to debit a Puppet's account
    /// @param _amount The amount to debit
    /// @param _asset The address of the Asset
    /// @param _puppet The address of the Puppet
    function debitPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    /// @notice The ```creditPuppetAccount``` function is called by a Route to credit a Puppet's account
    /// @param _amount The amount to credit
    /// @param _asset The address of the Asset
    /// @param _puppet The address of the Puppet
    function creditPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    /// @notice The ```updateLastPositionOpenedTimestamp``` function is called by a Route to update the last position opened timestamp of a Puppet
    /// @param _puppet The address of the Puppet
    /// @param _routeType The RouteType key
    function updateLastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external;

    /// @notice The ```sendFunds``` function is called by a Route to send funds to a _receiver
    /// @param _amount The amount to send
    /// @param _asset The address of the Asset
    /// @param _receiver The address of the receiver
    function sendFunds(uint256 _amount, address _asset, address _receiver) external;

    /// @notice The ```sendFundsToVault``` function is called by a Route to emit an event on GMX callback
    /// @param _requestKey The request key
    /// @param _isExecuted The boolean indicating if the request is executed
    /// @param _isIncrease The boolean indicating if the request is an increase or decrease request
    function emitCallback(bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external;

    // Authority

    // called by keeper

    /// @notice The ```decreaseSize``` function is called by Puppet keepers to decrease the position size in case there are Puppets to adjust
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _executionFee The total execution fee, paid by the Keeper in ETH
    /// @param _routeKey The Route key
    /// @return _requestKey The request key
    function decreaseSize(IRoute.AdjustPositionParams memory _adjustPositionParams, uint256 _executionFee, bytes32 _routeKey) external payable returns (bytes32 _requestKey);

    /// @notice The ```liquidate``` function is called by Puppet keepers to reset the Route's accounting in case of a liquidation
    /// @param _routeKey The Route key
    function liquidate(bytes32 _routeKey) external;

    // called by owner

    /// @notice The ```rescueTokens``` function is called by the Authority to rescue tokens from this contract
    /// @param _amount The amount to rescue
    /// @param _token The address of the Token
    /// @param _receiver The address of the receiver
    function rescueTokens(uint256 _amount, address _token, address _receiver) external;

    /// @notice The ```rescueRouteTokens``` function is called by the Authority to rescue tokens from a Route
    /// @param _amount The amount to rescue
    /// @param _token The address of the Token
    /// @param _receiver The address of the receiver
    /// @param _route The address of the Route
    function rescueRouteTokens(uint256 _amount, address _token, address _receiver, address _route) external;

    /// @notice The ```freezeRoute``` function is called by the Authority to freeze or unfreeze a Route
    /// @param _route The address of the Route
    /// @param _freeze Whether to freeze or unfreeze
    function freezeRoute(address _route, bool _freeze) external;

    /// @notice The ```setRouteType``` function is called by the Authority to set a new RouteType
    /// @param _collateral The address of the Collateral Token
    /// @param _index The address of the Index Token
    /// @param _isLong The boolean value of the position
    function setRouteType(address _collateral, address _index, bool _isLong) external;

    /// @notice The ```setGMXInfo``` function is called by the Authority to set the GMX contract addresses
    /// @param _gmxRouter The address of the GMX Router
    /// @param _gmxVault The address of the GMX Vault
    /// @param _gmxPositionRouter The address of the GMX Position Router
    function setGMXInfo(address _gmxRouter, address _gmxVault, address _gmxPositionRouter) external;

    /// @notice The ```setKeeper``` function is called by the Authority to set the Keeper address
    /// @param _keeperAddr The address of the new Keeper
    function setKeeper(address _keeperAddr) external;

    /// @notice The ```setReferralCode``` function is called by the Authority to set the referral code
    /// @param _refCode The new referral code
    function setReferralCode(bytes32 _refCode) external;

    /// @notice The ```setRouteFactory``` function is called by the Authority to set the Route Factory address
    /// @param _factory The address of the new Route Factory
    function setRouteFactory(address _factory) external;

    /// @notice The ```setFeeDivisors``` function is called by the Authority to pause all Routes
    /// @param _pause The new pause state
    function pause(bool _pause) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event RegisterRoute(address indexed trader, address indexed route, bytes32 indexed routeTypeKey);
    event RequestPositionAdjustment(address indexed caller, address indexed route, bytes32 indexed requestKey, bytes32 routeTypeKey);
    event ApprovePlugin(address indexed caller, bytes32 indexed routeTypeKey);
    event Deposit(uint256 indexed amount, address indexed asset, address caller, address indexed puppet);
    event Withdraw(uint256 amount, address indexed asset, address indexed receiver, address indexed puppet);
    event Subscribe(address[] traders, uint256[] allowances, address indexed puppet, bytes32 indexed routeTypeKey, bool indexed subscribe);
    event SetThrottleLimit(address indexed puppet, bytes32 indexed routeType, uint256 throttleLimit);
    event DebitPuppet(uint256 amount, address indexed asset, address indexed puppet, address indexed caller);
    event CreditPuppet(uint256 amount, address indexed asset, address indexed puppet, address indexed caller);
    event UpdateOpenTimestamp(address indexed puppet, bytes32 indexed routeType, uint256 timestamp);
    event Send(uint256 amount, address indexed asset, address indexed receiver, address indexed caller);
    event Callback(address indexed route, bytes32 indexed requestKey, bool indexed isExecuted, bool isIncrease);
    event DecreaseSize(bytes32 indexed requestKey, bytes32 indexed routeKey);
    event Liquidate(bytes32 indexed routeKey);
    event SetRouteType(bytes32 routeTypeKey, address collateral, address index, bool isLong);
    event SetGMXUtils(address gmxRouter, address gmxVault, address gmxPositionRouter);
    event Pause(bool paused);
    event SetReferralCode(bytes32 indexed referralCode);
    event SetRouteFactory(address indexed factory);
    event Keeper(address indexed keeper);
    event RouteRescue(uint256 amount, address indexed token, address indexed receiver, address indexed route);
    event Rescue(uint256 amount, address indexed token, address indexed receiver);
    event FreezeRoute(address indexed route, bool indexed freeze);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotRoute();
    error RouteTypeNotRegistered();
    error RouteAlreadyRegistered();
    error MismatchedInputArrays();
    error RouteNotRegistered();
    error InvalidAllowancePercentage();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidAmount();
    error InvalidAsset();
    error ZeroBytes32();
    error RouteWaitingForCallback();
}
