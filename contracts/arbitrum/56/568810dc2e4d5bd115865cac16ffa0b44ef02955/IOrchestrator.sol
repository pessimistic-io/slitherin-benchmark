// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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

    // Authority

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

    /// @notice The ```requestRoutePosition``` function is called by the Authority to create a new position request for a Route
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @param _route The address of the Route
    /// @param _isIncrease Whether to increase or decrease the position
    /// @return _requestKey The Request key
    function requestRoutePosition(IRoute.AdjustPositionParams memory _adjustPositionParams, IRoute.SwapParams memory _swapParams, uint256 _executionFee, address _route, bool _isIncrease) external payable returns (bytes32 _requestKey);

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
    /// @param _keeperAddr The address of the Keeper
    function setKeeper(address _keeperAddr) external;

    /// @notice The ```setReferralCode``` function is called by the Authority to set the referral code
    /// @param _refCode The referral code
    function setReferralCode(bytes32 _refCode) external;

    /// @notice The ```setFeeDivisors``` function is called by the Authority to pause all Routes
    /// @param _pause The new pause state
    function pause(bool _pause) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event RouteRegistered(address indexed _trader, address indexed _route, bytes32 indexed _routeTypeKey);
    event Deposited(uint256 indexed _amount, address indexed _asset, address _caller, address indexed _puppet);
    event Withdrawn(uint256 _amount, address indexed _asset, address indexed _receiver, address indexed _puppet);
    event RoutesSubscriptionUpdated(address[] _traders, uint256[] _allowances, address indexed _puppet, bytes32 indexed _routeTypeKey, bool indexed _subscribe);
    event ThrottleLimitSet(address indexed _puppet, bytes32 indexed _routeType, uint256 _throttleLimit);
    event PuppetAccountDebited(uint256 _amount, address indexed _asset, address indexed _puppet, address indexed _caller);
    event PuppetAccountCredited(uint256 _amount, address indexed _asset, address indexed _puppet, address indexed _caller);
    event LastPositionOpenedTimestampUpdated(address indexed _puppet, bytes32 indexed _routeType, uint256 _timestamp);
    event FundsSent(uint256 _amount, address indexed _asset, address indexed _receiver, address indexed _caller);
    event RouteTypeSet(bytes32 _routeTypeKey, address _collateral, address _index, bool _isLong);
    event GMXUtilsSet(address _gmxRouter, address _gmxVault, address _gmxPositionRouter);
    event Paused(bool _paused);
    event ReferralCodeSet(bytes32 indexed _referralCode);
    event KeeperSet(address indexed _keeper);
    event PositionRequestCreated(bytes32 indexed _requestKey, address indexed _route, bool indexed _isIncrease);
    event RouteTokensRescued(uint256 _amount, address indexed _token, address indexed _receiver, address indexed _route);
    event TokensRescued(uint256 _amount, address indexed _token, address indexed _receiver);
    event RouteFrozen(address indexed _route, bool indexed _freeze);

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
