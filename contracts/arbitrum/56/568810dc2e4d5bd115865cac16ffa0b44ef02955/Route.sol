// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ========================= Route ==============================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/Puppet

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IGMXRouter} from "./IGMXRouter.sol";
import {IGMXPositionRouter} from "./IGMXPositionRouter.sol";
import {IGMXVault} from "./IGMXVault.sol";

import {IRoute} from "./IRoute.sol";

import "./Base.sol";

/// @title Route
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice This contract acts as a container account which a trader can use to manage their position, and puppets can subscribe to
contract Route is Base, IRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public frozen;

    uint256 public positionIndex;

    bytes32 private immutable _routeTypeKey;

    mapping(bytes32 => bool) public keeperRequests; // requestKey => isKeeperRequest

    mapping(bytes32 => uint256) public requestKeyToAddCollateralRequestsIndex; // requestKey => addCollateralRequestsIndex
    mapping(uint256 => AddCollateralRequest) public addCollateralRequests; // addCollateralIndex => AddCollateralRequest
    mapping(uint256 => Position) public positions; // positionIndex => Position

    IOrchestrator public orchestrator;

    Route public route;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _orchestrator The address of the ```Orchestrator``` contract
    /// @param _trader The address of the trader
    /// @param _collateralToken The address of the collateral token
    /// @param _indexToken The address of the index token
    /// @param _isLong Whether the route is long or short
    constructor(address _orchestrator, address _trader, address _collateralToken, address _indexToken, bool _isLong) {
        orchestrator = IOrchestrator(_orchestrator);

        route.trader = _trader;
        route.collateralToken = _collateralToken;
        route.indexToken = _indexToken;
        route.isLong = _isLong;

        _routeTypeKey = orchestrator.getRouteTypeKey(_collateralToken, _indexToken, _isLong);

        IGMXRouter(orchestrator.gmxRouter()).approvePlugin(orchestrator.gmxPositionRouter());
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Modifier that ensures the caller is the trader or the orchestrator, and that the route is not frozen or paused
    modifier onlyTrader() {
        if (msg.sender != route.trader && msg.sender != address(orchestrator)) revert NotTrader();
        if (orchestrator.paused()) revert Paused();
        if (frozen) revert RouteFrozen();
        _;
    }

    /// @notice Modifier that ensures the caller is the orchestrator
    modifier onlyOrchestrator() {
        if (msg.sender != address(orchestrator)) revert NotOrchestrator();
        _;
    }

    /// @notice Modifier that ensures the caller is the keeper
    modifier onlyKeeper() {
        if (msg.sender != orchestrator.keeper()) revert NotKeeper();
        _;
    }

    /// @notice Modifier that ensures the caller is the callback caller
    modifier onlyCallbackCaller() {
        if (msg.sender != orchestrator.gmxPositionRouter()) revert NotCallbackCaller();
        _;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // Position Info

    /// @inheritdoc IRoute
    function puppets() external view returns (address[] memory _puppets) {
        _puppets = positions[positionIndex].puppets;
    }

    /// @inheritdoc IRoute
    function participantShares(address _participant) external view returns (uint256 _shares) {
        _shares = positions[positionIndex].participantShares[_participant];
    }

    /// @inheritdoc IRoute
    function latestAmountIn(address _participant) external view returns (uint256 _amountIn) {
        _amountIn = positions[positionIndex].latestAmountIn[_participant];
    }

    /// @inheritdoc IRoute
    function isPuppetAdjusted(address _puppet) external view returns (bool _isAdjusted) {
        _isAdjusted = positions[positionIndex].adjustedPuppets[_puppet];
    }

    // Request Info

    /// @inheritdoc IRoute
    function puppetsRequestAmounts(bytes32 _requestKey) external view returns (uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts) {
        uint256 _index = requestKeyToAddCollateralRequestsIndex[_requestKey];
        _puppetsShares = addCollateralRequests[_index].puppetsShares;
        _puppetsAmounts = addCollateralRequests[_index].puppetsAmounts;
    }

    /// @inheritdoc IRoute
    function isWaitingForCallback() external view returns (bool) {
        bytes32[] memory _requests = positions[positionIndex].requestKeys;
        IGMXPositionRouter _positionRouter = IGMXPositionRouter(orchestrator.gmxPositionRouter());
        for (uint256 _i = 0; _i < _requests.length; _i++) {
            address[] memory _increasePath = _positionRouter.getIncreasePositionRequestPath(_requests[_i]);
            address[] memory _decreasePath = _positionRouter.getDecreasePositionRequestPath(_requests[_i]);
            if (_increasePath.length > 0 || _decreasePath.length > 0) {
                return true;
            }
        }

        return false;
    }

    // ============================================================================================
    // Trader Functions
    // ============================================================================================

    /// @inheritdoc IRoute
    // slither-disable-next-line reentrancy-eth
    function requestPosition(
        AdjustPositionParams memory _adjustPositionParams,
        SwapParams memory _swapParams,
        uint256 _executionFee,
        bool _isIncrease
    ) external payable onlyTrader nonReentrant returns (bytes32 _requestKey) {

        _repayBalance(bytes32(0), msg.value, false);

        if (_isIncrease) {
            uint256 _amountIn = _getAssets(_swapParams, _executionFee);
            _requestKey = _requestIncreasePosition(_adjustPositionParams, _amountIn, _executionFee);
        } else {
            _requestKey = _requestDecreasePosition(_adjustPositionParams, _executionFee);
        }
    }

    /// @inheritdoc IRoute
    function approvePlugin() external onlyTrader nonReentrant {
        IGMXRouter(orchestrator.gmxRouter()).approvePlugin(orchestrator.gmxPositionRouter());

        emit PluginApproved();
    }

    // ============================================================================================
    // Keeper Functions
    // ============================================================================================

    /// @inheritdoc IRoute
    function decreaseSize(AdjustPositionParams memory _adjustPositionParams, uint256 _executionFee) external onlyKeeper nonReentrant returns (bytes32 _requestKey) {
        keeperRequests[_requestKey] = true;
        _requestKey = _requestDecreasePosition(_adjustPositionParams, _executionFee);
    }

    /// @inheritdoc IRoute
    function liquidate() external onlyKeeper nonReentrant {
        if (_isOpenInterest()) revert PositionStillAlive();

        _repayBalance(bytes32(0), 0, false);

        emit Liquidated();
    }

    // ============================================================================================
    // Callback Function
    // ============================================================================================

    // @inheritdoc IPositionRouterCallbackReceiver
    function gmxPositionCallback(bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external onlyCallbackCaller nonReentrant {
        if (_isExecuted) {
            if (_isIncrease) _allocateShares(_requestKey);
            _requestKey = bytes32(0);
        }

        _repayBalance(_requestKey, 0, keeperRequests[_requestKey]);

        emit CallbackReceived(_requestKey, _isExecuted, _isIncrease);
    }

    // ============================================================================================
    // Orchestrator Function
    // ============================================================================================

    /// @inheritdoc IRoute
    function rescueTokens(uint256 _amount, address _token, address _receiver) external {
        if (_token == address(0)) {
            payable(_receiver).sendValue(_amount);
        } else {
            IERC20(_token).safeTransfer(_receiver, _amount);
        }

        emit TokensRescued(_amount, _token, _receiver);
    }

    /// @inheritdoc IRoute
    function freeze(bool _freeze) external {
        frozen = _freeze;

        emit Frozen(_freeze);
    }

    // ============================================================================================
    // Internal Mutated Functions
    // ============================================================================================

    /// @notice The ```_getAssets``` function is used to get the assets of the Trader and Puppets and update the request accounting
    /// @dev This function is called by ```requestPosition```
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _executionFee The execution fee paid by the Trader, in ETH
    /// @return _amountIn The total amount of collateral Puppets and Traders are requesting to add to the position
    // slither-disable-next-line reentrancy-eth
    function _getAssets(SwapParams memory _swapParams, uint256 _executionFee) internal returns (uint256 _amountIn) {
        if (_swapParams.amount > 0) {
            // 1. get trader assets and allocate request shares. pull funds too, if needed
            uint256 _traderAmountIn = _getTraderAssets(_swapParams, _executionFee);

            uint256 _traderShares = _convertToShares(0, 0, _traderAmountIn);
        
            uint256 _totalSupply = _traderShares;
            uint256 _totalAssets = _traderAmountIn;

            // 2. get puppets assets and allocate request shares
            bytes memory _puppetsRequestData = _getPuppetsAssetsAndAllocateRequestShares(_totalSupply, _totalAssets);

            uint256 _puppetsAmountIn;
            uint256[] memory _puppetsShares;
            uint256[] memory _puppetsAmounts;
            (
                _puppetsAmountIn,
                _totalSupply,
                _totalAssets,
                _puppetsShares,
                _puppetsAmounts
            ) = abi.decode(_puppetsRequestData, (uint256, uint256, uint256, uint256[], uint256[]));

            // 3. store request data
            AddCollateralRequest memory _request = AddCollateralRequest({
                puppetsAmountIn: _puppetsAmountIn,
                traderAmountIn: _traderAmountIn,
                traderShares: _traderShares,
                totalSupply: _totalSupply,
                totalAssets: _totalAssets,
                puppetsShares: _puppetsShares,
                puppetsAmounts: _puppetsAmounts
            });

            uint256 _positionIndex = positionIndex;
            addCollateralRequests[positions[_positionIndex].addCollateralRequestsIndex] = _request;
            positions[_positionIndex].addCollateralRequestsIndex += 1;

            // 4. pull funds from Orchestrator
            orchestrator.sendFunds(_puppetsAmountIn, route.collateralToken, address(this));

            return (_puppetsAmountIn + _traderAmountIn);
        }
    }

    /// @notice The ```_getTraderAssets``` function is used to get the assets of the Trader
    /// @dev This function is called by ```_getAssets```
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _executionFee The execution fee paid by the Trader, in ETH
    /// @return _traderAmountIn The total amount of collateral the Trader is requesting to add to the position
    function _getTraderAssets(SwapParams memory _swapParams, uint256 _executionFee) internal returns (uint256 _traderAmountIn) {
        if (msg.value - _executionFee > 0) {
            if (msg.value - _executionFee != _swapParams.amount) revert InvalidExecutionFee();
            if (_swapParams.path[0] != _WETH) revert InvalidPath();

            payable(_WETH).functionCallWithValue(abi.encodeWithSignature("deposit()"), _swapParams.amount);
        } else {
            if (msg.value != _executionFee) revert InvalidExecutionFee();

            // slither-disable-next-line arbitrary-send-erc20
            IERC20(_swapParams.path[0]).safeTransferFrom(route.trader, address(this), _swapParams.amount);
        }

        if (_swapParams.path[0] == route.collateralToken) {
            _traderAmountIn = _swapParams.amount;
        } else {
            address _toToken = _swapParams.path[_swapParams.path.length - 1];
            if (_toToken != route.collateralToken) revert InvalidPath();

            address _router = orchestrator.gmxRouter();
            _approve(_router, _swapParams.path[0], _swapParams.amount);

            uint256 _before = IERC20(_toToken).balanceOf(address(this));
            IGMXRouter(_router).swap(_swapParams.path, _swapParams.amount, _swapParams.minOut, address(this));
            _traderAmountIn = IERC20(_toToken).balanceOf(address(this)) - _before;
        }
    }

    /// @notice The ```_getPuppetsAssetsAndAllocateRequestShares``` function is used to get the assets of the Puppets and allocate request shares
    /// @dev This function is called by ```_getAssets```
    /// @param _totalSupply The current total supply of shares in the request
    /// @param _totalAssets The current total assets in the request
    /// @return _puppetsRequestData The request data of the Puppets, encoded as bytes
    function _getPuppetsAssetsAndAllocateRequestShares(uint256 _totalSupply, uint256 _totalAssets) internal returns (bytes memory _puppetsRequestData) {
        bool _isOI = _isOpenInterest();
        uint256 _traderAmountIn = _totalAssets;
        uint256 _increaseRatio = _isOI ? _traderAmountIn * 1e18 / positions[positionIndex].latestAmountIn[route.trader] : 0;

        uint256 _puppetsAmountIn = 0;
        address[] memory _puppets = _getRelevantPuppets(_isOI);
        uint256[] memory _puppetsShares = new uint256[](_puppets.length);
        uint256[] memory _puppetsAmounts = new uint256[](_puppets.length);

        GetPuppetAdditionalAmountContext memory _context = GetPuppetAdditionalAmountContext({
            isOI: _isOI,
            increaseRatio: _increaseRatio,
            traderAmountIn: _traderAmountIn
        });

        for (uint256 i = 0; i < _puppets.length; i++) {
            (uint256 _additionalAmount, uint256 _additionalShares) = _getPuppetAmounts(
                _context,
                _totalSupply,
                _totalAssets,
                _puppets[i]
            );

            if (_additionalAmount > 0) {
                orchestrator.debitPuppetAccount(_additionalAmount, route.collateralToken, _puppets[i]);

                _puppetsAmountIn = _puppetsAmountIn + _additionalAmount;

                _totalSupply = _totalSupply + _additionalShares;
                _totalAssets = _totalAssets + _additionalAmount;
            }

            _puppetsShares[i] = _additionalShares;
            _puppetsAmounts[i] = _additionalAmount;
        }

        _puppetsRequestData = abi.encode(
            _puppetsAmountIn,
            _totalSupply,
            _totalAssets,
            _puppetsShares,
            _puppetsAmounts
        );
    }

    /// @notice The ```_getRelevantPuppets``` function is used to get the relevant Puppets for the request and update the Position's Puppets, if needed
    /// @dev This function is called by ```_getPuppetsAssetsAndAllocateRequestShares```
    /// @param _isOI A boolean indicating if the request is adding to an already opened position
    /// @return _puppets The relevant Puppets for the request
    function _getRelevantPuppets(bool _isOI) internal returns (address[] memory _puppets) {
        Position storage _position = positions[positionIndex];
        if (_isOI) {
            _puppets = _position.puppets;
        } else {
            _puppets = orchestrator.subscribedPuppets(orchestrator.getRouteKey(route.trader, _routeTypeKey));
            _position.puppets = _puppets;
        }
    }

    /// @notice The ```_getPuppetAmounts``` function is used to get the additional amount and shares for a Puppet
    /// @dev This function is called by ```_getPuppetsAssetsAndAllocateRequestShares```
    /// @param _context The context of the request
    /// @param _totalSupply The current total supply of shares in the request
    /// @param _totalAssets The current total assets in the request
    /// @param _puppet The Puppet address
    /// @return _additionalAmount The additional amount the Puppet has to deposit
    /// @return _additionalShares The additional shares for the deposit
    function _getPuppetAmounts(
        GetPuppetAdditionalAmountContext memory _context,
        uint256 _totalSupply,
        uint256 _totalAssets,
        address _puppet
    ) internal returns (uint256 _additionalAmount, uint256 _additionalShares) {
        Position storage _position = positions[positionIndex];

        uint256 _allowancePercentage = orchestrator.puppetAllowancePercentage(_puppet, address(this));
        uint256 _allowanceAmount = (orchestrator.puppetAccountBalance(_puppet, route.collateralToken) * _allowancePercentage) / 100;

        if (_context.isOI) {
            if (_position.adjustedPuppets[_puppet]) {
                _additionalAmount = 0;
            } else {
                uint256 _requiredAdditionalCollateral = _position.latestAmountIn[_puppet] * _context.increaseRatio / 1e18;
                if (_requiredAdditionalCollateral > _allowanceAmount || _requiredAdditionalCollateral == 0) {
                    _position.adjustedPuppets[_puppet] = true;
                    _additionalAmount = 0;
                } else {
                    _additionalAmount = _requiredAdditionalCollateral;
                    _additionalShares = _convertToShares(_totalAssets, _totalSupply, _allowanceAmount);
                }
            }
        } else {
            if (_allowanceAmount > 0 && orchestrator.isBelowThrottleLimit(_puppet, _routeTypeKey)) {
                _additionalAmount = _allowanceAmount > _context.traderAmountIn ? _context.traderAmountIn : _allowanceAmount;
                _additionalShares = _convertToShares(_totalAssets, _totalSupply, _allowanceAmount);
                orchestrator.updateLastPositionOpenedTimestamp(_puppet, _routeTypeKey);
            } else {
                _additionalAmount = 0;
            }
        }
    }

    /// @notice The ```_requestIncreasePosition``` function is used to create a request to increase the position size and/or collateral
    /// @dev This function is called by ```requestPosition```
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _amountIn The total amount of collateral to increase the position by
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @return _requestKey The request key of the request
    function _requestIncreasePosition(AdjustPositionParams memory _adjustPositionParams, uint256 _amountIn, uint256 _executionFee) internal returns (bytes32 _requestKey) {
        address[] memory _path = new address[](1);
        _path[0] = route.collateralToken;

        _approve(orchestrator.gmxRouter(), _path[0], _amountIn);

        // slither-disable-next-line arbitrary-send-eth
        _requestKey = IGMXPositionRouter(orchestrator.gmxPositionRouter()).createIncreasePosition{ value: _executionFee } (
            _path,
            route.indexToken,
            _amountIn,
            _adjustPositionParams.minOut,
            _adjustPositionParams.sizeDelta,
            route.isLong,
            _adjustPositionParams.acceptablePrice,
            _executionFee,
            orchestrator.referralCode(),
            address(this)
        );

        positions[positionIndex].requestKeys.push(_requestKey);

        if (_amountIn > 0) requestKeyToAddCollateralRequestsIndex[_requestKey] = positions[positionIndex].addCollateralRequestsIndex - 1;

        emit CreatedIncreasePositionRequest(
            _requestKey,
            _adjustPositionParams.amountIn,
            _adjustPositionParams.minOut,
            _adjustPositionParams.sizeDelta,
            _adjustPositionParams.acceptablePrice
        );
    }

    /// @notice The ```_requestDecreasePosition``` function is used to create a request to decrease the position size and/or collateral
    /// @dev This function is called by ```requestPosition```
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @return _requestKey The request key of the request
    function _requestDecreasePosition(AdjustPositionParams memory _adjustPositionParams, uint256 _executionFee) internal returns (bytes32 _requestKey) {
        if (msg.value != _executionFee) revert InvalidExecutionFee();

        address[] memory _path = new address[](1);
        _path[0] = route.collateralToken;

        // slither-disable-next-line arbitrary-send-eth
        _requestKey = IGMXPositionRouter(orchestrator.gmxPositionRouter()).createDecreasePosition{ value: _executionFee } (
            _path,
            route.indexToken,
            _adjustPositionParams.collateralDelta,
            _adjustPositionParams.sizeDelta,
            route.isLong,
            address(this), // _receiver
            _adjustPositionParams.acceptablePrice,
            _adjustPositionParams.minOut,
            _executionFee,
            false, // _withdrawETH
            address(this)
        );

        positions[positionIndex].requestKeys.push(_requestKey);

        emit CreatedDecreasePositionRequest(
            _requestKey,
            _adjustPositionParams.minOut,
            _adjustPositionParams.collateralDelta,
            _adjustPositionParams.sizeDelta,
            _adjustPositionParams.acceptablePrice
        );
    }

    /// @notice The ```_allocateShares``` function is used to update the position accounting with the request data
    /// @dev This function is called by ```gmxPositionCallback```
    /// @param _requestKey The request key of the request
    function _allocateShares(bytes32 _requestKey) internal {
        AddCollateralRequest memory _request = addCollateralRequests[requestKeyToAddCollateralRequestsIndex[_requestKey]];
        uint256 _traderAmountIn = _request.traderAmountIn;
        if (_traderAmountIn > 0) {
            Route memory _route = route;
            Position storage _position = positions[positionIndex];
            uint256 _totalSupply = _position.totalSupply;
            uint256 _totalAssets = _position.totalAssets;
            address[] memory _puppets = _position.puppets;
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _puppetAmountIn = _request.puppetsAmounts[i];
                if (_puppetAmountIn > 0) {
                    uint256 _newPuppetShares = _convertToShares(_totalAssets, _totalSupply, _puppetAmountIn);

                    _position.participantShares[_puppet] += _newPuppetShares;

                    _position.latestAmountIn[_puppet] = _puppetAmountIn;

                    _totalSupply = _totalSupply + _newPuppetShares;
                    _totalAssets = _totalAssets + _puppetAmountIn;
                }
            }

            uint256 _newTraderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);

            _position.participantShares[_route.trader] += _newTraderShares;

            _position.latestAmountIn[_route.trader] = _traderAmountIn;

            _totalSupply = _totalSupply + _newTraderShares;
            _totalAssets = _totalAssets + _traderAmountIn;

            _position.totalSupply = _totalSupply;
            _position.totalAssets = _totalAssets;
        }
    }

    /// @notice The ```_repayBalance``` function is used to repay the balance of the Route
    /// @dev This function is called by ```requestPosition```, ```liquidate``` and ```gmxPositionCallback```
    /// @param _requestKey The request key of the request, expected to be `bytes32(0)` if called on a successful request
    /// @param _traderAmountIn The amount ETH paid by the trader before this function is called
    /// @param _repayKeeper A boolean indicating whether the keeper should be repaid the unused execution fee
    function _repayBalance(bytes32 _requestKey, uint256 _traderAmountIn, bool _repayKeeper) internal {
        Position storage _position = positions[positionIndex];
        Route memory _route = route;

        if (!_isOpenInterest()) {
            _resetRoute();
        }

        uint256 _totalAssets = IERC20(_route.collateralToken).balanceOf(address(this));
        if (_totalAssets > 0) {
            uint256 _puppetsAssets = 0;
            uint256 _totalSupply = 0;
            uint256 _balance = _totalAssets;
            bool _isFailedRequest = _requestKey != bytes32(0);
            address[] memory _puppets = _position.puppets;
            AddCollateralRequest memory _request = addCollateralRequests[requestKeyToAddCollateralRequestsIndex[_requestKey]];
            for (uint256 i = 0; i < _puppets.length; i++) {
                uint256 _shares;
                address _puppet = _puppets[i];
                if (_isFailedRequest) {
                    if (i == 0) _totalSupply = _request.totalSupply;
                    _shares = _request.puppetsShares[i];
                } else {
                    if (i == 0) _totalSupply = _position.totalSupply;
                    _shares = _position.participantShares[_puppet];
                }

                if (_shares > 0) {
                    uint256 _assets = _convertToAssets(_balance, _totalSupply, _shares);

                    orchestrator.creditPuppetAccount(_assets, _route.collateralToken, _puppet);

                    _totalSupply -= _shares;
                    _balance -= _assets;

                    _puppetsAssets += _assets;
                }
            }

            uint256 _traderShares = _isFailedRequest ? _request.traderShares : _position.participantShares[_route.trader];
            uint256 _traderAssets = _convertToAssets(_balance, _totalSupply, _traderShares);

            IERC20(_route.collateralToken).safeTransfer(address(orchestrator), _puppetsAssets);
            IERC20(_route.collateralToken).safeTransfer(_route.trader, _traderAssets);
        }

        uint256 _ethBalance = address(this).balance;
        if ((_ethBalance - _traderAmountIn) > 0) {
            address _executionFeeReceiver = _repayKeeper ? orchestrator.keeper() : _route.trader;
            payable(_executionFeeReceiver).sendValue(_ethBalance - _traderAmountIn);
        }

        emit BalanceRepaid(_totalAssets);
    }

    /// @notice The ```_resetRoute``` function is used to increment the position index, which is used to track the current position
    /// @dev This function is called by ```_repayBalance```, only if there's no open interest
    function _resetRoute() internal {
        positionIndex += 1;

        emit RouteReset();
    }

    /// @notice The ```_approve``` function is used to approve a spender to spend a token
    /// @dev This function is called by ```_getTraderAssets``` and ```_requestIncreasePosition```
    /// @param _spender The address of the spender
    /// @param _token The address of the token
    /// @param _amount The amount of the token to approve
    function _approve(address _spender, address _token, uint256 _amount) internal {
        IERC20(_token).safeApprove(_spender, 0);
        IERC20(_token).safeApprove(_spender, _amount);
    }

    // ============================================================================================
    // Internal View Functions
    // ============================================================================================

    /// @notice The ```_isOpenInterest``` function is used to indicate whether the Route has open interest
    /// @dev This function is called by ```liquidate```, ```_getPuppetsAssetsAndAllocateRequestShares``` and ```_repayBalance```
    /// @return bool A boolean indicating whether the Route has open interest
    function _isOpenInterest() internal view returns (bool) {
        Route memory _route = route;

        (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(orchestrator.gmxVault()).getPosition(address(this), _route.collateralToken, _route.indexToken, _route.isLong);

        return _size > 0 && _collateral > 0;
    }

    /// @notice The ```_convertToShares``` function is used to convert an amount of assets to shares, given the total assets and total supply
    /// @param _totalAssets The total assets
    /// @param _totalSupply The total supply
    /// @param _assets The amount of assets to convert
    /// @return _shares The amount of shares
    function _convertToShares(uint256 _totalAssets, uint256 _totalSupply, uint256 _assets) internal pure returns (uint256 _shares) {
        if (_assets == 0) revert ZeroAmount();

        if (_totalAssets == 0) {
            _shares = _assets;
        } else {
            _shares = (_assets * _totalSupply) / _totalAssets;
        }

        if (_shares == 0) revert ZeroAmount();
    }

    /// @notice The ```_convertToAssets``` function is used to convert an amount of shares to assets, given the total assets and total supply
    /// @param _totalAssets The total assets
    /// @param _totalSupply The total supply
    /// @param _shares The amount of shares to convert
    /// @return _assets The amount of assets
    function _convertToAssets(uint256 _totalAssets, uint256 _totalSupply, uint256 _shares) internal pure returns (uint256 _assets) {
        if (_shares == 0) revert ZeroAmount();

        if (_totalSupply == 0) {
            _assets = _shares;
        } else {
            _assets = (_shares * _totalAssets) / _totalSupply;
        }

        if (_assets == 0) revert ZeroAmount();
    }

    // ============================================================================================
    // Receive Function
    // ============================================================================================

    receive() external payable {}
}
