// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";
import "./Ownable.sol";
import "./IVaultPriceFeed.sol";
import "./IWETH.sol";
import "./IVault.sol";
import "./ITradeStorage.sol";
import "./IESBT.sol";


contract RouterSign is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public weth;
    address public vault;
    address public esbt;
    address public priceFeed;
    address public tradeStorage;

    mapping (address => uint256) public swapMaxRatio;

    event Swap(address account, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    // event IncreasePosition(address[] _path, address _indexToken, uint256 _amountIn, uint256 _sizeDelta, bool _isLong, uint256 _price,
    //         bytes[] _updaterSignedMsg);
    // event DecreasePosition(address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _price,
    //             bytes[] _updaterSignedMsg);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }
    
    constructor(address _vault, address _weth) {
        vault = _vault;
        weth = _weth;
    }

    function initialize(address _priceFeed, address _esbt, address _tradeStorage) external onlyOwner {
        priceFeed = _priceFeed;
        esbt = _esbt;
        tradeStorage = _tradeStorage;
    }

    function setMaxSwapRatio(address _token, uint256 _ratio) external onlyOwner{
        swapMaxRatio[_token] = _ratio;
    }

    function withdrawToken(address _account, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }
    
    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }
    

    function increasePositionAndUpdate(address[] memory _path, address _indexToken, uint256 _amountIn, uint256 _sizeDelta, bool _isLong, uint256 _price,
            bytes[] memory _updaterSignedMsg) external nonReentrant{
        require(_amountIn > 0, "zero amount in");
        require(IVault(vault).isFundingToken(_path[0]), "not funding token");
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        IERC20(_path[0]).safeTransferFrom(_sender(), vault, _amountIn);
        if (_path.length > 1) {
            uint256 amountOut = _swap(_path, 0, address(this), msg.sender);
            IERC20(_path[_path.length - 1]).safeTransfer(vault, amountOut);
        }
        _increasePosition(_path[_path.length - 1], _indexToken, _sizeDelta, _isLong);
    }

    function increasePositionETHAndUpdate(address[] memory _path, address _indexToken, uint256 _sizeDelta, bool _isLong, uint256 _price,
                bytes[] memory _updaterSignedMsg) external payable nonReentrant{
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        require(_path[0] == weth, "Router: invalid _path");
        uint256 increaseValue = msg.value;
        require(increaseValue > 0, "Router: zero amount in");
        _transferETHToVault(increaseValue);
        if (_path.length > 1) {
            uint256 amountOut = _swap(_path, 0, address(this), msg.sender);
            IERC20(_path[_path.length - 1]).safeTransfer(vault, amountOut);
        }
        _increasePosition(_path[_path.length - 1], _indexToken, _sizeDelta, _isLong);
    }

    function decreasePositionAndUpdate(address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _price,
                bytes[] memory _updaterSignedMsg) external nonReentrant  {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        _decreasePosition(_collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);
    }

    function decreasePositionETHAndUpdate(address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address payable _receiver, uint256 _price,
                bytes[] memory _updaterSignedMsg) external nonReentrant {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        uint256 amountOut = _decreasePosition(_collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, address(this));
        _transferOutETH(amountOut, _receiver);
    }

    function decreasePositionAndSwapUpdate(address[] memory _path, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _price, uint256 _minOut,
                bytes[] memory _updaterSignedMsg) external nonReentrant {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        uint256 amount = _decreasePosition(_path[0], _indexToken, _collateralDelta, _sizeDelta, _isLong, address(this));
        IERC20(_path[0]).safeTransfer(vault, amount);
        _swap(_path, _minOut, _receiver, msg.sender);
    }

    function decreasePositionAndSwapETHUpdate(address[] memory _path, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address payable _receiver, uint256 , uint256 _minOut,
                bytes[] memory _updaterSignedMsg) external nonReentrant {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        require(_path[_path.length - 1] == weth, "Router: invalid _path");
        uint256 amount = _decreasePosition(_path[0], _indexToken, _collateralDelta, _sizeDelta, _isLong, address(this));
        IERC20(_path[0]).safeTransfer(vault, amount);
        uint256 amountOut = _swap(_path, _minOut, address(this), msg.sender);
        _transferOutETH(amountOut, _receiver);
    }


    function directPoolDeposit(address _token, uint256 _amount) external {
        require(IVault(vault).isFundingToken(_token), "not funding token");
        IERC20(_token).safeTransferFrom(_sender(), vault, _amount);
        IVault(vault).directPoolDeposit(_token);
    }


    function validSwap(address _token, uint256 _amount) public view returns(bool){
        require(IVault(vault).isFundingToken(_token), "not funding token");
        if (swapMaxRatio[_token] == 0) return true;
        address[] memory fundingTokenList = IVault(vault).fundingTokenList();
        uint256 aum = 0;
        uint256 token_mt = IVaultPriceFeed(priceFeed).tokenToUsdUnsafe(_token, _amount, true);
        for (uint256 i = 0; i < fundingTokenList.length; i++) {
            address token = fundingTokenList[i];
            uint256 price =  IVaultPriceFeed(priceFeed).getPriceUnsafe(token, true, true, true);
            VaultMSData.TokenBase memory tBae = IVault(vault).getTokenBase(token);
            uint256 poolAmount = tBae.poolAmount;
            uint256 decimals = IVault(vault).tokenDecimals(token);
            poolAmount = poolAmount.mul(price).div(10 ** decimals);
            if (token == _token){
                token_mt = token_mt.add(poolAmount);
            }
            poolAmount = poolAmount > IVault(vault).guaranteedUsd(token) ? poolAmount.sub(IVault(vault).guaranteedUsd(token)) : 0;
            aum = aum.add(poolAmount);
        }
        if (aum == 0) return true;
        return token_mt.mul(1000).div(aum) < swapMaxRatio[_token];
    }

    function swap(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver, bytes[] memory _updaterSignedMsg) external payable nonReentrant {
        require(validSwap(_path[0], _amountIn), "Swap limit reached.");
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        IERC20(_path[0]).safeTransferFrom(_sender(), vault, _amountIn);
        uint256 amountOut = _swap(_path, _minOut, _receiver, msg.sender);
        emit Swap(msg.sender, _path[0], _path[_path.length - 1], _amountIn, amountOut);
    }

    function swapETHToTokens(address[] memory _path, uint256 _minOut, address _receiver, bytes[] memory _updaterSignedMsg) external payable nonReentrant {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        require(_path[0] == weth, "Router: invalid _path");
        require(validSwap(_path[0], msg.value), "Swap limit reached.");
        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).safeTransfer(vault, msg.value);        
        uint256 amountOut = _swap(_path, _minOut, _receiver, msg.sender);
        emit Swap(msg.sender, _path[0], _path[_path.length - 1], msg.value, amountOut);
    }

    function swapTokensToETH(address[] memory _path, uint256 _amountIn, uint256 _minOut, address payable _receiver, bytes[] memory _updaterSignedMsg) external payable nonReentrant {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        require(validSwap(_path[0], _amountIn), "Swap limit reached.");
        require(_path[_path.length - 1] == weth, "Router: invalid _path");
        IERC20(_path[0]).safeTransferFrom(_sender(), vault, _amountIn);
        uint256 amountOut = _swap(_path, _minOut, address(this), msg.sender);
        _transferOutETH(amountOut, _receiver);
        emit Swap(msg.sender, _path[0], _path[_path.length - 1], _amountIn, amountOut);
    }



    //------------------------------ Private Functions ------------------------------
    function _increasePosition(address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) private {
        address tradeAccount = _sender();
        IVault(vault).increasePosition(tradeAccount, _collateralToken, _indexToken, _sizeDelta, _isLong);
        IESBT(esbt).updateTradingScoreForAccount(tradeAccount, vault, _sizeDelta, 0);
        ITradeStorage(tradeStorage).updateTrade(tradeAccount, _sizeDelta);
    }

    function _decreasePosition(address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) private returns (uint256) {
        address tradeAccount = _sender();
        IESBT(esbt).updateTradingScoreForAccount(tradeAccount, vault, _sizeDelta, 100);
        ITradeStorage(tradeStorage).updateTrade(tradeAccount, _sizeDelta);
        return IVault(vault).decreasePosition(tradeAccount, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);
    }

    function _transferETHToVault(uint256 _value) private {
        IWETH(weth).deposit{value: _value}();
        IERC20(weth).safeTransfer(vault, _value);
    }

    function _transferOutETH(uint256 _amountOut, address payable _receiver) private {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    function _swap(address[] memory _path, uint256 _minOut, address _receiver, address _user) private returns (uint256) {
        if (_path.length == 2) {
            return _vaultSwap(_path[0], _path[1], _minOut, _receiver, _user);
        }
        if (_path.length == 3) {
            uint256 midOut = _vaultSwap(_path[0], _path[1], 0, address(this), _user);
            IERC20(_path[1]).safeTransfer(vault, midOut);
            return _vaultSwap(_path[1], _path[2], _minOut, _receiver, _user);
        }

        revert("Router: invalid _path.length");
    }

    function _vaultSwap(address _tokenIn, address _tokenOut, uint256 _minOut, address _receiver, address _account) private returns (uint256) {
        uint256 amountOut = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);
        require(amountOut >= _minOut, "Router: amountOut not satisfied.");
        uint256 _sizeDelta = IVaultPriceFeed(priceFeed).tokenToUsdUnsafe(_tokenOut, amountOut,false);
        IESBT(esbt).updateSwapScoreForAccount(_account, vault, _sizeDelta);
        ITradeStorage(tradeStorage).updateSwap(_account, _sizeDelta);
        return amountOut;
    }

    function _sender() private view returns (address) {
        return msg.sender;
    }


}

