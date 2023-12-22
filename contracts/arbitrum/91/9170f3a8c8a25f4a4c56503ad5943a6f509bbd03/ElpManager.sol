// SPDX-License-Identifier: MIT

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Address.sol";
import "./VaultMSData.sol";
import "./IVault.sol";
import "./IElpManager.sol";
import "./IUSDX.sol";
import "./IMintable.sol";
import "./IWETH.sol";
import "./IESBT.sol";
import "./IVaultPriceFeed.sol";


pragma solidity ^0.8.0;

contract ElpManager is ReentrancyGuard, Ownable, IElpManager {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant USDX_DECIMALS = 10 ** 18;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;
    uint256 public constant WEIGHT_PRECISSION = 1000000;

    IVault public vault;
    address public elp;
    address public weth;
    address public esbt;
    address public priceFeed;

    uint256 public aumAddition;
    uint256 public aumDeduction;

    bool public inPrivateMode;
    mapping(address => bool) public isHandler;

    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInUsdx,
        uint256 elpSupply,
        uint256 usdxAmount,
        uint256 mintAmount
    );

    event RemoveLiquidity(
        address account,
        address token,
        uint256 elpAmount,
        uint256 aumInUsdx,
        uint256 elpSupply,
        uint256 usdxAmount,
        uint256 amountOut
    );
    event AumUpdate(uint256 aumInUSD, uint256 elpSupply);
     
    receive() external payable {
        require(msg.sender == weth, "invalid sender");
    }

    constructor(address _vault, address _elp, address _weth) {
        vault = IVault(_vault);
        elp = _elp;
        weth = _weth;
    }
    
    function setAddress(address _priceFeed, address _esbt) external onlyOwner {
        priceFeed = _priceFeed;
        esbt = _esbt;
    }
    function withdrawToken(address _account, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }
    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }
    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }
    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyOwner {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }
    function setInPrivateMode(bool _inPrivateMode) external {
        _validateHandler();
        inPrivateMode = _inPrivateMode;
    }
    //--- End of owner setting
    function getUpdateFee(bytes[] memory _priceUpdateData) public view returns (uint256) {
        return IVaultPriceFeed(priceFeed).getUpdateFee(_priceUpdateData);
    }
    function addLiquidityAndUpdate(address _token, uint256 _amount, uint256 _minElp, bytes[] memory _priceUpdateData) external payable nonReentrant returns (uint256) {
        if (inPrivateMode) { revert("ElpManager: action not enabled"); }
        require(vault.isFundingToken(_token), "[ElpMabager] Not funding Token");
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        return _addLiquidity(msg.sender, msg.sender, _token, _amount, _minElp);
    }
    function addLiquidityETHAndUpdate(uint256 _minElp, bytes[] memory _priceUpdateData) external payable nonReentrant returns (uint256) {
        if (inPrivateMode) { revert("ElpManager: action not enabled"); }
        require(vault.isFundingToken(weth), "[ElpMabager] Not funding Token");
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        if (msg.value < 1) {
            return 0;
        }
        return _addLiquidity(msg.sender, msg.sender, address(0), msg.value, _minElp);
    }
    function addLiquidity(address _token, uint256 _amount, uint256 , uint256 _minElp) external payable override nonReentrant returns (uint256) {
        _validateHandler();
        require(vault.isFundingToken(_token), "[ElpMabager] Not funding Token");
        if (inPrivateMode) { revert("ElpManager: action not enabled"); }
        return _addLiquidity(msg.sender, msg.sender, _token, _amount, _minElp);
    }
    function addLiquidityETH() external nonReentrant payable override returns (uint256) {
        _validateHandler();
        require(vault.isFundingToken(weth), "[ElpMabager] Not funding Token");
        if (inPrivateMode) { revert("ElpManager: action not enabled"); }
        return _addLiquidity(msg.sender, msg.sender, address(0), msg.value, 0);
    }
    function _addLiquidity(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minElp) private returns (uint256) {
        require(_fundingAccount != address(0), "zero address");
        require(_account != address(0), "ElpManager: zero address");
        require(_amount > 0, "ElpManager: invalid amount");
        // calculate aum before buyUSDX
        uint256 aumInUSD = getAumInUSDSafe(true);
        uint256 elpSupply = IERC20(elp).totalSupply();
        if (_token != address(0)){
            IERC20(_token).safeTransferFrom(_fundingAccount, address(vault), _amount);
        }else{
            IWETH(weth).deposit{value: msg.value}();
            IERC20(weth).transfer(address(vault), msg.value);
            _token = weth;
        }
        uint256 usdxAmount = vault.buyUSDX(_token, address(this));
        uint256 mintAmount = aumInUSD == 0 ? usdxAmount : usdxAmount.mul(elpSupply).div(aumInUSD);
        require(mintAmount >= _minElp, "min output not satisfied");
        IMintable(elp).mint(_account, mintAmount);
        IESBT(esbt).updateAddLiqScoreForAccount(_account, address(vault), usdxAmount.div(USDX_DECIMALS).mul(PRICE_PRECISION), 0);
        emit AddLiquidity(_account, _token, _amount, aumInUSD, elpSupply, usdxAmount, mintAmount); 
        emit AumUpdate(aumInUSD, elpSupply);
        return mintAmount;
    }


    function removeLiquidityAndUpdate(address _tokenOut, uint256 _elpAmount, uint256 _minOut, address _receiver, bytes[] memory _priceUpdateData) external payable nonReentrant returns (uint256) {
        require(vault.isFundingToken(_tokenOut), "[ElpMabager] Not funding Token");
        if (inPrivateMode) { revert("ElpManager: action not enabled"); }
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        return _removeLiquidity(msg.sender, _tokenOut, _elpAmount, _minOut, _receiver);
    }
    function removeLiquidityETHAndUpdate(uint256 _elpAmount, bytes[] memory _priceUpdateData) external payable nonReentrant returns (uint256) {
        require(vault.isFundingToken(weth), "[ElpMabager] ETH Not funding Token");
        if (inPrivateMode) { revert("ElpManager: action not enabled"); }
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        address _account = msg.sender;
        uint256 _amountOut =  _removeLiquidity(msg.sender, weth, _elpAmount, 0, address(this));
        IWETH(weth).withdraw(_amountOut);
        payable(_account).sendValue(_amountOut);
        return _amountOut;
    }
    function removeLiquidity(address _tokenOut, uint256 _elpAmount, uint256 _minOut, address _receiver) external payable override nonReentrant returns (uint256) {
        require(vault.isFundingToken(_tokenOut), "[ElpMabager] Not funding Token");
        _validateHandler();
        if (inPrivateMode) { revert("ElpManager: action not enabled"); }
        return _removeLiquidity(msg.sender, _tokenOut, _elpAmount, _minOut, _receiver);
    }
    function removeLiquidityETH(uint256 _elpAmount) external nonReentrant payable override returns (uint256) {
        require(vault.isFundingToken(weth), "[ElpMabager] Not funding Token");
        _validateHandler();
        if (inPrivateMode) { revert("ElpManager: action not enabled"); }
        address _account = msg.sender;
        uint256 _amountOut =  _removeLiquidity(msg.sender, weth, _elpAmount, 0, address(this));
        IWETH(weth).withdraw(_amountOut);
        payable(_account).sendValue(_amountOut);
        return _amountOut;
    }

    function _removeLiquidity(address _account, address _tokenOut, uint256 _elpAmount, uint256 _minOut, address _receiver) private returns (uint256) {
        require(_account != address(0), " transfer from the zero address");
        require(_elpAmount > 0, "ElpManager: invalid _elpAmount");
        require(IERC20(elp).balanceOf(_account) >= _elpAmount, "insufficient ELP");
        // calculate aum before sellUSDX
        uint256 aumInUSD = getAumInUSDSafe(false);
        uint256 elpSupply = IERC20(elp).totalSupply();
        uint256 usdxAmount = _elpAmount.mul(aumInUSD).div(elpSupply);
        IERC20(elp).safeTransferFrom(_account, address(this),_elpAmount );
        IMintable(elp).burn(address(this), _elpAmount);
        uint256 amountOut = vault.sellUSDX(_tokenOut, _receiver, usdxAmount);
        require(amountOut >= _minOut, "ElpManager: insufficient output");
        IESBT(esbt).updateAddLiqScoreForAccount(_account, address(vault), usdxAmount.div(USDX_DECIMALS).mul(PRICE_PRECISION), 100);
        emit RemoveLiquidity(_account, _tokenOut, _elpAmount, aumInUSD, elpSupply, usdxAmount, amountOut);
        emit AumUpdate(aumInUSD, elpSupply);
        return amountOut;
    }


    function getPoolInfo() public view returns (uint256[] memory) {
        uint256[] memory poolInfo = new uint256[](4);
        poolInfo[0] = getAum(true);
        poolInfo[1] = 0;//getAumSimple(true);
        poolInfo[2] = IERC20(elp).totalSupply();
        poolInfo[3] = IVault(vault).usdxSupply();
        return poolInfo;
    }
    function getPoolTokenList() public view returns (address[] memory) {
        return vault.fundingTokenList();
    }
    function getPoolTokenInfo(address _token) public view returns (uint256[] memory, int256[] memory) {
        // require(vault.whitelistedTokens(_token), "invalid token");
        // require(vault.isFundingToken(_token) || vault.isTradingToken(_token), "not )
        uint256[] memory tokenInfo_U= new uint256[](8);       
        int256[] memory tokenInfo_I = new int256[](4);       
        VaultMSData.TokenBase memory tBae = vault.getTokenBase(_token);
        VaultMSData.TradingFee memory tFee = vault.getTradingFee(_token);

        tokenInfo_U[0] = vault.totalTokenWeights() > 0 ? tBae.weight.mul(1000000).div(vault.totalTokenWeights()) : 0;
        tokenInfo_U[1] = tBae.poolAmount > 0 ? tBae.reservedAmount.mul(1000000).div(tBae.poolAmount) : 0;
        tokenInfo_U[2] = tBae.poolAmount;//vault.getTokenBalance(_token).sub(vault.feeReserves(_token)).add(vault.feeSold(_token));
        tokenInfo_U[3] = IVaultPriceFeed(priceFeed).getPriceUnsafe(_token, true, false, false);
        tokenInfo_U[4] = IVaultPriceFeed(priceFeed).getPriceUnsafe(_token, false, false, false);
        tokenInfo_U[5] = tFee.fundingRatePerSec;
        tokenInfo_U[6] = tFee.accumulativefundingRateSec;
        tokenInfo_U[7] = tFee.latestUpdateTime;

        tokenInfo_I[0] = tFee.longRatePerSec;
        tokenInfo_I[1] = tFee.shortRatePerSec;
        tokenInfo_I[2] = tFee.accumulativeLongRateSec;
        tokenInfo_I[3] = tFee.accumulativeShortRateSec;

        return (tokenInfo_U, tokenInfo_I);
    }


    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    function getAumInUSDSafe(bool maximise) public view returns (uint256) {
        uint256 aum = getAumSafe(maximise);
        return aum.mul(USDX_DECIMALS).div(PRICE_PRECISION);
    }

    function getAumInUSD(bool maximise) public view returns (uint256) {
        uint256 aum = getAum(maximise);
        return aum.mul(USDX_DECIMALS).div(PRICE_PRECISION);
    }


    function getAumInUSDX(bool maximise) public view returns (uint256) {
        uint256 aum = getAum(maximise);
        return aum.mul(USDX_DECIMALS).div(PRICE_PRECISION);
    }

    function getAumSafe(bool maximise) public view returns (uint256) {
        address[] memory fundingTokenList = vault.fundingTokenList();
        address[] memory tradingTokenList = vault.tradingTokenList();
        uint256 aum = aumAddition;
        uint256 userShortProfits = 0;
        uint256 userLongProfits = 0;

        for (uint256 i = 0; i < fundingTokenList.length; i++) {
            address token = fundingTokenList[i];
            uint256 price = IVaultPriceFeed(priceFeed).getPrice(token, maximise, false, false);
            VaultMSData.TokenBase memory tBae = vault.getTokenBase(token);
            uint256 poolAmount = tBae.poolAmount;
            uint256 decimals = vault.tokenDecimals(token);
            poolAmount = poolAmount.mul(price).div(10 ** decimals);
            poolAmount = poolAmount > vault.guaranteedUsd(token) ? poolAmount.sub(vault.guaranteedUsd(token)) : 0;
            aum = aum.add(poolAmount);
        }

        for (uint256 i = 0; i < tradingTokenList.length; i++) {
            address token = tradingTokenList[i];
            VaultMSData.TradingRec memory tradingRec = vault.getTradingRec(token);

            uint256 price = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, maximise, false, false);
            uint256 shortSize = tradingRec.shortSize;
            if (shortSize > 0){
                uint256 averagePrice = tradingRec.shortAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = shortSize.mul(priceDelta).div(averagePrice);
                if (price > averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userShortProfits = userShortProfits.add(delta);
                }    
            }

            uint256 longSize = tradingRec.longSize;
            if (longSize > 0){
                uint256 averagePrice = tradingRec.longAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = longSize.mul(priceDelta).div(averagePrice);
                if (price < averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userLongProfits = userLongProfits.add(delta);
                }    
            }
        }

        uint256 _totalUserProfits = userLongProfits.add(userShortProfits);
        aum = _totalUserProfits > aum ? 0 : aum.sub(_totalUserProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);  
    }


    function getAum(bool maximise) public view returns (uint256) {
        address[] memory fundingTokenList = vault.fundingTokenList();
        address[] memory tradingTokenList = vault.tradingTokenList();
        uint256 aum = aumAddition;
        uint256 userShortProfits = 0;
        uint256 userLongProfits = 0;

        for (uint256 i = 0; i < fundingTokenList.length; i++) {
            address token = fundingTokenList[i];
            uint256 price = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, maximise, false, false);
            VaultMSData.TokenBase memory tBae = vault.getTokenBase(token);
            uint256 poolAmount = tBae.poolAmount;
            uint256 decimals = vault.tokenDecimals(token);
            poolAmount = poolAmount.mul(price).div(10 ** decimals);
            poolAmount = poolAmount > vault.guaranteedUsd(token) ? poolAmount.sub(vault.guaranteedUsd(token)) : 0;
            aum = aum.add(poolAmount);
        }

        for (uint256 i = 0; i < tradingTokenList.length; i++) {
            address token = tradingTokenList[i];
            VaultMSData.TradingRec memory tradingRec = vault.getTradingRec(token);

            uint256 price = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, maximise, false, false);
            uint256 shortSize = tradingRec.shortSize;
            if (shortSize > 0){
                uint256 averagePrice = tradingRec.shortAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = shortSize.mul(priceDelta).div(averagePrice);
                if (price > averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userShortProfits = userShortProfits.add(delta);
                }    
            }

            uint256 longSize = tradingRec.longSize;
            if (longSize > 0){
                uint256 averagePrice = tradingRec.longAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = longSize.mul(priceDelta).div(averagePrice);
                if (price < averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userLongProfits = userLongProfits.add(delta);
                }    
            }
        }

        uint256 _totalUserProfits = userLongProfits.add(userShortProfits);
        aum = _totalUserProfits > aum ? 0 : aum.sub(_totalUserProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);  
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender] || msg.sender == owner(), "ElpManager: forbidden");
    }
}


