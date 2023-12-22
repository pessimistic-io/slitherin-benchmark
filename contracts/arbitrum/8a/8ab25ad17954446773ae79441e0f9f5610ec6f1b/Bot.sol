// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Context.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";
import "./interfaces_IERC20.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";

import {IPositionRouter} from "./IPositionRouter.sol";
import {IVault} from "./IVault.sol";
import {IRouter} from "./IRouter.sol";
import {IRouter} from "./IRouter.sol";
import {BotFactory} from "./BotFactory.sol";
import "./console.sol";

contract Bot is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct User {
        address account;
        uint256 fixedMargin;
        uint256 positionLimit;
        uint256 takeProfit;
        uint256 stopLoss;
        uint256 level;
    }

    struct IncreasePositionRequest {
        address account;
        address trader;
        bytes32 requestKey;
        address[] path;
        address indexToken;
        uint256 amountIn;
        uint256 sizeDelta;
        bool isLong;
        bool reverted;
    }

    struct DecreasePositionRequest {
        address account;
        address trader;
        address[] path;
        address indexToken;
        uint256 amountOut;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        uint256 realisedPnl;
        bool isRealisedPnl;
    }

    mapping (uint256 => IncreasePositionRequest) public increasePositionRequests;
    mapping (uint256 => DecreasePositionRequest) public decreasePositionRequests;
    mapping (address => address) public followTokenTrader;

    mapping (address => uint256) public increasePositionCount;
    mapping (address => uint256) public decreasePositionCount;

    mapping (address => bool) public isBotKeeper;

    mapping (bytes32 => bytes32) public properties;

    User public user;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    address public adminAddress;
    address public tokenPlay;
    address public positionRouter;
    address public vault;
    address public router;
    address public botFactory;

    EnumerableSet.AddressSet private _traderAddressSet;
    EnumerableSet.AddressSet private _tokenAddressSet;

    event SetSetting(uint256 fixedMargin, uint256 positionLimit, uint256 takeProfit, uint256 stopLoss);
    event SetProperty(bytes32 key, bytes32 value);
    event AddFollowTokenTrader(address indexed token, address trader);
    event RemoveFollowTokenTrader(address indexed token, address trader);

    event CreateIncreasePosition(
        address indexed account,
        address trader,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    );

    event CreateDecreasePosition(
        address indexed account,
        address trader,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver
    );

    constructor(
        address _tokenPlay,
        address _positionRouter,
        address _vault,
        address _router,
        address _botFactory,
        address _userAddress
    ) {
        tokenPlay = _tokenPlay;

        positionRouter = _positionRouter;
        vault = _vault;
        router = _router;
        botFactory = _botFactory;
        user.account = _userAddress;

        _setApprovePlugin();
    }

    // Modifier for execution roles
    modifier onlyBotKeeper() {
        require(BotFactory(botFactory).isBotKeeper(_msgSender()) == true, "Bot: Not is bot Keeper");
        _;
    }

    modifier onlyBotFactory() {
        require(botFactory == _msgSender(), "Bot: Not is bot factory");
        _;
    }

    modifier onlyUser() {
        require(user.account == msg.sender, "Bot: Not is user");
        _;
    }

    modifier onlyBotKeeperAndUser() {
        require((BotFactory(botFactory).isBotKeeper(_msgSender()) == true) || (user.account == msg.sender), "Bot: Not is bot Keeper");
        _;
    }

    function _setApprovePlugin() internal {
        IRouter(router).approvePlugin(positionRouter);
    }

    // collect token when GMX cancel position
    function botFactoryCollectToken(uint256 _index) external nonReentrant onlyBotFactory returns (bool) {
        IncreasePositionRequest storage position = increasePositionRequests[_index];
        require(!position.reverted, "Bot: position already reverted");

        uint256 botBalance = IERC20(tokenPlay).balanceOf(address(this));
        uint256 amount = botBalance > position.amountIn ? position.amountIn : botBalance;

        IERC20(tokenPlay).safeTransfer(botFactory, amount);
        position.reverted = true;

        return true;
    }

    function createIncreasePosition(
        address _trader,
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee
    ) external payable nonReentrant onlyBotKeeperAndUser returns (bool) {
        require(msg.value == _executionFee, "val");
        require(_path.length == 1 || _path.length == 2, "len");
        require(_path[0] == tokenPlay, "Wrong token play");
        require(followTokenTrader[_indexToken] == _trader, "Operations: Trader not added");
        
        uint256 amountIn = BotFactory(botFactory).botRequestToken(user.account, _amountIn);
        
        require(amountIn <= IERC20(tokenPlay).balanceOf(address(this)), "Bot: not enough balance for create increase position");
        require(amountIn > 0, "Bot: amountIn > 0");
        
        IERC20(tokenPlay).approve(router, amountIn);
        bytes32 key = IPositionRouter(positionRouter).createIncreasePosition{value: msg.value}(
            _path,
            _indexToken,
            amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            BotFactory(botFactory).referralCode(),
            0x0000000000000000000000000000000000000000
        );

        increasePositionCount[user.account] += 1;
        uint256 count = increasePositionCount[user.account];

        increasePositionRequests[count] = IncreasePositionRequest({
            account: user.account,
            trader: _trader,
            requestKey: key,
            path: _path,
            indexToken: _indexToken,
            amountIn: _amountIn,
            sizeDelta: _sizeDelta,
            isLong: _isLong,
            reverted: false
        });

        emit CreateIncreasePosition(
            user.account,
            _trader,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee
        );

        return true;
    }

    function _getRealisedPnl(
        address[] memory _path,
        address _indexToken,
        bool _isLong,
        uint256 _collateralDelta
    ) internal view returns (uint256 realisedPnlPerTrade, bool isRealisedPnlPerTrade) {
        (, uint256 collateral, , , , uint256 realisedPnl, bool isRealisedPnl, ) = IVault(vault).getPosition(address(this), _path[0], _indexToken, _isLong);

        isRealisedPnlPerTrade = isRealisedPnl;

        if (_collateralDelta == collateral) {
            realisedPnlPerTrade = realisedPnl;
        } else if (collateral > 0) {
            realisedPnlPerTrade = (((_collateralDelta * BASIS_POINTS_DIVISOR) / collateral) * realisedPnl) / BASIS_POINTS_DIVISOR;
        }
    }

    function _getPosition(
        address _indexToken,
        address _collateralToken,
        bool _isLong
    )
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool,
            uint256
        )
    {
        return IVault(vault).getPosition(address(this), _collateralToken, _indexToken, _isLong);
    }

    function closePosition(
        address _trader,
        address[] memory _path,
        address _indexToken,
        bool _isLong,
        uint256 _minOut
    ) external nonReentrant onlyBotKeeperAndUser returns (bool) {
        require(_path.length == 1 || _path.length == 2, "len");
        require(followTokenTrader[_indexToken] == _trader, "Operations: Trader not added");
        (uint256 _sizeDelta,, , , , , , ) = _getPosition(_indexToken, _path[0], _isLong);

        (uint256 realisedPnl, bool isRealisedPnl) = _getRealisedPnl(_path, _indexToken, _isLong, 0);
        address receiver = _path.length > 1 ? address(this) : address(botFactory);
        uint256 amountOut = _decreasePosition(
            address(this),
            _path[0],
            _indexToken,
            0,
            _sizeDelta,
            _isLong,
            address(receiver)
        );
        if (_path.length > 1) {
            IERC20(_path[0]).safeTransfer(vault, amountOut);
            amountOut = _vaultSwap(_path[0], _path[1], _minOut, address(botFactory));
        }
        BotFactory(botFactory).botRequestUpdateBalance(user.account, _trader, amountOut, realisedPnl, isRealisedPnl);

        decreasePositionCount[user.account] += 1;
        uint256 count = decreasePositionCount[user.account];

        decreasePositionRequests[count] = DecreasePositionRequest({
            account: user.account,
            trader: _trader,
            path: _path,
            indexToken: _indexToken,
            amountOut: amountOut,
            collateralDelta: 0,
            sizeDelta: _sizeDelta,
            isLong: _isLong,
            realisedPnl: realisedPnl,
            isRealisedPnl: isRealisedPnl
        });

        emit CreateDecreasePosition(
            user.account,
            _trader,
            _path,
            _indexToken,
            0,
            _sizeDelta,
            _isLong,
            address(botFactory)
        );

        return true;
    }

    function createDecreasePosition(
        address _trader,
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _minOut
    ) external nonReentrant onlyBotKeeperAndUser returns (bool) {
        require(_path.length == 1 || _path.length == 2, "len");
        require(followTokenTrader[_indexToken] == _trader, "Operations: Trader not added");

        (uint256 realisedPnl, bool isRealisedPnl) = _getRealisedPnl(_path, _indexToken, _isLong, _collateralDelta);

        address receiver = _path.length > 1 ? address(this) : address(botFactory);
        uint256 amountOut = _decreasePosition(address(this), _path[0], _indexToken, _collateralDelta, _sizeDelta, _isLong, receiver);

        if (_path.length > 1) {
            IERC20(_path[0]).safeTransfer(vault, amountOut);
            amountOut = _vaultSwap(_path[0], _path[1], _minOut, address(botFactory));
        }
        
        BotFactory(botFactory).botRequestUpdateBalance(user.account, _trader, amountOut, realisedPnl, isRealisedPnl);

        decreasePositionCount[user.account] += 1;
        uint256 count = decreasePositionCount[user.account];
        
        decreasePositionRequests[count] = DecreasePositionRequest({
            account: user.account,
            trader: _trader,
            path: _path,
            indexToken: _indexToken,
            amountOut: amountOut,
            collateralDelta: _collateralDelta,
            sizeDelta: _sizeDelta,
            isLong: _isLong,
            realisedPnl: realisedPnl,
            isRealisedPnl: isRealisedPnl
        });

        emit CreateDecreasePosition(
            user.account,
            _trader,
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            address(botFactory)
        );

        return true;
    }

    function setSetting(
        uint256 _fixedMargin,
        uint256 _positionLimit,
        uint256 _takeProfit,
        uint256 _stopLoss
    ) external onlyUser {
        user.fixedMargin = _fixedMargin;
        user.positionLimit = _positionLimit;
        user.takeProfit = _takeProfit;
        user.stopLoss = _stopLoss;

        emit SetSetting(_fixedMargin, _positionLimit, _takeProfit, _stopLoss);
    }

    function setProperty(bytes32 _key, bytes32 _value) external onlyUser {
        properties[_key] = _value;

        emit SetProperty(_key, _value);
    }

    function addFollowTrader(address _token, address _trader) external onlyUser {
        require(_trader != address(0), "Operations: Trader invalid");
        require(_token != address(0), "Operations: Token invalid");
        if (followTokenTrader[_token] != address(0)) {
            emit RemoveFollowTokenTrader(_token, _trader);
        }
        followTokenTrader[_token] = _trader;

        if (!_tokenAddressSet.contains(_token)) {
            _tokenAddressSet.add(_token);
        }

        emit AddFollowTokenTrader(_token, _trader);
    }

    function removeFollowTrader(address _token, address _trader) external onlyUser {
        require(_tokenAddressSet.contains(_token), "Operations: Token not added");
        
        followTokenTrader[_token] = address(0);
        _tokenAddressSet.remove(_token);
        
        emit RemoveFollowTokenTrader(_token, _trader);
    }

    /*
     * @notice View addresses and details for all the collections available for trading
     * @param cursor: cursor
     * @param size: size of the response
     */
    function viewFollowTokenTraders(uint256 cursor, uint256 size)
        external
        view
        returns (
            address[] memory tokenAddresses,
            uint256
        )
    {
        uint256 length = size;

        if (length > _tokenAddressSet.length() - cursor) {
            length = _tokenAddressSet.length() - cursor;
        }

        tokenAddresses = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            tokenAddresses[i] = _tokenAddressSet.at(cursor + i);
        }

        return (tokenAddresses, cursor + length);
    }

    function _vaultSwap(address _tokenIn, address _tokenOut, uint256 _minOut, address _receiver) internal returns (uint256) {
        uint256 amountOut = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);
        require(amountOut >= _minOut, "BasePositionManager: insufficient amountOut");
        return amountOut;
    }

    function _decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) internal returns (uint256) {
        uint256 amountOut = IVault(vault).decreasePosition(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);

        return amountOut;
    }
}
