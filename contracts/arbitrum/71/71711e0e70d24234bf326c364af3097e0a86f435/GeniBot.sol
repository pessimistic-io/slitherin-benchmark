// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Context.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";
import "./IERC20.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

import {IPositionRouter} from "./IPositionRouter.sol";
import {IVault} from "./IVault.sol";
import {IRouter} from "./IRouter.sol";
import {IGeniVault} from "./IGeniVault.sol";
import {IWETH} from "./IWETH.sol";

contract GeniBot is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
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

    mapping (address => address) public followTokenTrader;
    mapping (bytes32 => bytes32) public properties;

    User public user;
    bool private _init;
    bool public botOn;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    address public adminAddress;
    address public tokenPlay;
    address public positionRouter;
    address public vault;
    address public router;
    address public botFactory;

    address public weth;
    address public usdc;

    mapping(address => mapping(address => mapping(bool => uint256))) public increasePositionFees;

    EnumerableSet.AddressSet private _traderAddressSet;
    EnumerableSet.AddressSet private _tokenAddressSet;

    event SetSetting(uint256 fixedMargin, uint256 positionLimit, uint256 takeProfit, uint256 stopLoss);
    event SetProperty(bytes32 key, bytes32 value);
    event AddFollowTokenTrader(address indexed token, address trader);
    event RemoveFollowTokenTrader(address indexed token, address trader);
    event SetOnOffBot(bool);
    event CreateDecreasePosition(
        address indexed trader,
        address indexToken,
        address collateralToken,
        bool isLong,
        uint256 realisedPnl,
        bool isRealisedPnl,
        uint256 geniFees
    );

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

    event CreateDecreasePositionVault(
        address indexed account,
        address trader,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver
    );

    event Log(string message);

    constructor() {}

    function initialize(
        address _tokenPlay,
        address _positionRouter,
        address _vault,
        address _router,
        address _botFactory,
        address _userAddress,
        uint256 _fixedMargin,
        uint256 _positionLimit,
        uint256 _takeProfit,
        uint256 _stopLoss
    ) external {
        require(_init == false, "Forbidden");
        
        tokenPlay = _tokenPlay;

        positionRouter = _positionRouter;
        vault = _vault;
        router = _router;
        botFactory = _botFactory;

        user.account = _userAddress;
        user.fixedMargin = _fixedMargin;
        user.positionLimit = _positionLimit;
        user.takeProfit = _takeProfit;
        user.stopLoss = _stopLoss;

        weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

        _setApprovePlugin();

        _init = true;
        botOn = true;
        
        emit SetSetting(_fixedMargin, _positionLimit, _takeProfit, _stopLoss);
    }

    // Modifier for execution roles
    modifier onlyBotKeeper() {
        require(IGeniVault(botFactory).getBotKeeper(_msgSender()) == true, "Bot: Not is bot Keeper");
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
        require((IGeniVault(botFactory).getBotKeeper(_msgSender()) == true) || (user.account == msg.sender), "Bot: Not is bot Keeper");
        _;
    }

    function _setApprovePlugin() internal {
        IRouter(router).approvePlugin(positionRouter);
    }

    // collect token when GMX cancel position
    function botFactoryCollectToken() external nonReentrant onlyBotFactory returns (uint256) {
        uint256 botBalance = IERC20(tokenPlay).balanceOf(address(this));
        require(botBalance > 0, "botFactoryCollectToken: collect token fail");
        IERC20(tokenPlay).safeTransfer(botFactory, botBalance);
        return botBalance;
    }

    function setOnOffBot() external nonReentrant onlyBotKeeperAndUser returns (bool) {
        emit SetOnOffBot(!botOn);
        return botOn = !botOn;
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
        require(botOn, "GeniBot: bot off");
        require(msg.value == _executionFee, "val");
        require(_path.length == 1 || _path.length == 2, "len");
        require(_path[0] == tokenPlay, "Wrong token play");
        require(followTokenTrader[_indexToken] == _trader, "Operations: Trader not added");
        
        uint256 amountIn = IGeniVault(botFactory).botRequestToken(user.account, _amountIn);
        
        require(amountIn <= IERC20(tokenPlay).balanceOf(address(this)), "Bot: not enough balance for create increase position");
        require(amountIn > 0, "Bot: amountIn > 0");
        
        IERC20(tokenPlay).approve(router, amountIn);
        IPositionRouter(positionRouter).createIncreasePosition{value: msg.value}(
            _path,
            _indexToken,
            amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            IGeniVault(botFactory).getReferralCode(),
            0x0000000000000000000000000000000000000000
        );

        _saveFeesIncreasePosition(_path[0], _indexToken, _isLong, _sizeDelta);

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

    function _saveFeesIncreasePosition(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) internal {
        (uint256 size, , ,uint256 entryFundingRate , , , ,) = _getPosition(_indexToken, _collateralToken, _isLong);

        uint256 feeUsd = getPositionFee(_sizeDelta);
        uint256 fundingFee = IVault(vault).getFundingFee(_collateralToken, size, entryFundingRate);
        feeUsd = feeUsd.add(fundingFee);
        increasePositionFees[_indexToken][_collateralToken][_isLong] += feeUsd;
    }

    function getUser() external view returns (
        address, 
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        User memory account = user; 
        return (
            account.account,
            account.fixedMargin,
            account.positionLimit,
            account.takeProfit,
            account.stopLoss,
            account.level
        );
    }

    function getTokenPlay() external view returns (address) {
        return tokenPlay;
    }

    function getPositionFee(uint256 _sizeDelta) public returns (uint256) {
        if (_sizeDelta == 0) { return 0; }
        uint256 afterFeeUsd = _sizeDelta.mul(BASIS_POINTS_DIVISOR.sub(IGeniVault(botFactory).getMarginFeeBasisPoints())).div(BASIS_POINTS_DIVISOR);
        return _sizeDelta.sub(afterFeeUsd);
    }

    function _getRealisedPnl(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) internal returns (uint256 realisedPnlPerTrade, bool isRealisedPnlPerTrade) {
        (uint256 size, , ,uint256 entryFundingRate , , , ,) = _getPosition(_indexToken, _collateralToken, _isLong);
        (bool hasProfit, uint256 delta) = IVault(vault).getPositionDelta(address(this), _collateralToken, _indexToken, _isLong);
        uint256 adjustedDelta = _sizeDelta.mul(delta).div(size);

        uint256 feeUsd = getPositionFee(_sizeDelta);
        uint256 fundingFee = IVault(vault).getFundingFee(_collateralToken, size, entryFundingRate);
        uint256 increaseFees = increasePositionFees[_indexToken][_collateralToken][_isLong];
        feeUsd = feeUsd.add(fundingFee).add(increaseFees);

        uint256 pnlUsd;
        bool realProfit;
        if (hasProfit) {
            if (adjustedDelta > feeUsd) {
                pnlUsd = adjustedDelta.sub(feeUsd);
                realProfit = true;
            } else {
                pnlUsd = feeUsd.sub(adjustedDelta);
                realProfit = false;
            }
        } else {
            pnlUsd = adjustedDelta.add(feeUsd);
            realProfit = false;
        }

        realisedPnlPerTrade = IVault(vault).usdToTokenMin(tokenPlay, pnlUsd);
        isRealisedPnlPerTrade = realProfit;
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

    function createDecreasePosition(
        address _trader,
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        address _callbackTarget
    ) external payable nonReentrant onlyBotKeeperAndUser {
        require(_path.length == 1 || _path.length == 2, "len");
        require(followTokenTrader[_indexToken] == _trader, "Operations: Trader not added");
        require(_path[_path.length - 1] == weth, "path require receive ETH");

        IPositionRouter(positionRouter).createDecreasePosition{value: msg.value}(
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            address(this),
            _acceptablePrice,
            _minOut,
            _executionFee,
            true,
            _callbackTarget
        );

        (uint256 realisedPnl, bool isRealisedPnl) = _getRealisedPnl(_path[0], _indexToken, _isLong, _sizeDelta);
        increasePositionFees[_indexToken][_path[0]][_isLong] = 0; // reset increase fees
        uint256 geniFees = IGeniVault(botFactory).botRequestUpdateFees(user.account, _trader, realisedPnl, isRealisedPnl);
        emit CreateDecreasePosition(_trader, _indexToken, _path[0], _isLong, realisedPnl, isRealisedPnl, geniFees);
    }

    receive() external payable {
        uint256 balanceEth = address(this).balance;
        
        if (balanceEth > 0) {
            _transferETHToVault();
            uint256 usdcAmount = _vaultSwap(weth, usdc, 0, address(botFactory));

            IGeniVault(botFactory).botRequestUpdateBalance(user.account, usdcAmount);
        } 
    }

    function _transferETHToVault() private {
        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).safeTransfer(vault, msg.value);
    }

    function createDecreasePositionVault(
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
        require(_path[_path.length - 1] != weth, "path require receive not ETH");

        (uint256 realisedPnl, bool isRealisedPnl) = _getRealisedPnl(_path[0], _indexToken, _isLong, _sizeDelta);
        increasePositionFees[_indexToken][_path[0]][_isLong] = 0; // reset increase fees

        address receiver = _path.length > 1 ? address(this) : address(botFactory);
        uint256 amountOut = _decreasePosition(address(this), _path[0], _indexToken, _collateralDelta, _sizeDelta, _isLong, receiver);

        if (_path.length > 1) {
            IERC20(_path[0]).safeTransfer(vault, amountOut);
            amountOut = _vaultSwap(_path[0], _path[1], _minOut, address(botFactory));
        }
        
        uint256 geniFees = IGeniVault(botFactory).botRequestUpdateBalanceAndFees(user.account, _trader, amountOut, realisedPnl, isRealisedPnl);
        emit CreateDecreasePosition(_trader, _indexToken, _path[0], _isLong, realisedPnl, isRealisedPnl, geniFees);

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
            _validateRemoveTrader(_token);

            emit RemoveFollowTokenTrader(_token, followTokenTrader[_token]);
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

        _validateRemoveTrader(_token);
        
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

    // claim pending rewards on bot factory
    function claimTraderReward(address _token) external nonReentrant onlyUser {
        IGeniVault(botFactory).claimPendingRevenue(_token);
    }

    function _validateRemoveTrader(address _token) private view {
        (uint256 sizeLong, , , , , , ,) = _getPosition(_token, _token, true);
        (uint256 sizeShort, , , , , , ,) = _getPosition(_token, tokenPlay, false);
        if(sizeLong > 0 || sizeShort > 0){
            revert("Bot: You must close all positon follow by trader.");
        }
    }
}
