// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./TransferHelper.sol";
import "./SingleLP.sol";
import "./ISingleLP.sol";
import "./ILpManager.sol";
import "./IHandler.sol";
import "./IDipxStorage.sol";
import "./IMixedLP.sol";
import "./ILP.sol";
import "./IPositionManager.sol";
import "./IVaultPriceFeed.sol";
import "./EnumerableSet.sol";
import "./IERC20Metadata.sol";
import "./IERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract LpManager is Initializable,OwnableUpgradeable, ILpManager, ReentrancyGuardUpgradeable{
  using EnumerableSet for EnumerableSet.AddressSet;

  IDipxStorage public dipxStorage;
  // collateralToken => lp token
  mapping(address => address) public override lpTokens;
  mapping(address => bool) public override isLpToken;
  mapping(address => bool) public override lpEnable;
  mapping(address => EnumerableSet.AddressSet) private accountPools;

  event CreatePool(address account, address collateralToken, address pool);
  event AddLiquidity(
    address to, 
    address collateralToken, 
    uint256 amountIn, 
    address pool, 
    uint256 liquidity, 
    uint256 lpPrice, 
    uint256 collateralPrice
  );

  event RemoveLiquidity(
    address to,
    address pool, 
    address receiveToken,
    uint256 liquidityIn,
    uint256 tokenOut,
    uint256 lpPrice,
    uint256 collateralPrice
  );

  constructor(){
  }

  receive() external payable{}

  function initialize(address _dipxStorage) public initializer{
    __Ownable_init();
    __ReentrancyGuard_init();

    dipxStorage = IDipxStorage(_dipxStorage);
  }

  function setPoolActive(address _pool, bool _isLp, bool _active) external override onlyOwner{
    require(_pool!=address(0), "Invalid pool");
    lpEnable[_pool] = _active;
    isLpToken[_pool] = _isLp;
  }

  function setDipxStorage(address _dipxStorage) external override onlyOwner{
    dipxStorage = IDipxStorage(_dipxStorage);
  }

  function getSupplyWithPnl(address _lpToken, bool _includeProfit, bool _includeLoss) public view override returns(uint256){
    require(isLpToken[_lpToken] && lpEnable[_lpToken], "Invalid pool");

    if(ILP(_lpToken).isMixed()){
      return IMixedLP(_lpToken).getSupplyWithPnl(_includeProfit, _includeLoss);
    }else{
      return ISingleLP(_lpToken).getSupplyWithPnl(address(dipxStorage), _includeProfit, _includeLoss);
    }
  }

  function _amountIn(address _collateralToken) private view returns(uint256){
    if(dipxStorage.isNativeCurrency(_collateralToken)){
      return address(this).balance;
    }

    return IERC20(_collateralToken).balanceOf(address(this));
  }

  function _safeTransfer(address _collateralToken,address _to,uint256 _amount) private{
    if(dipxStorage.isNativeCurrency(_collateralToken)){
      TransferHelper.safeTransferETH(_to, _amount);
    }else{
      TransferHelper.safeTransfer(_collateralToken, _to, _amount);
    }
  }

  function getPoolPrice(address _pool, bool _maximise,bool _includeProfit, bool _includeLoss) public override view returns(uint256){
    require(isLpToken[_pool], "Invalid pool");
    if(ILP(_pool).isMixed()){
      return IMixedLP(_pool).getPrice(_maximise, _includeProfit, _includeLoss);
    }else{
      return ISingleLP(_pool).getPrice(address(dipxStorage), _includeProfit, _includeLoss);
    }
  }

  function getAccountPoolLength(address _account) public override view returns(uint256){
    return accountPools[_account].length();
  }
  function getAccountPoolAt(address _account, uint256 _index) public override view returns(address){
    return accountPools[_account].at(_index);
  }

  function updatePools(address _account, address _pool) public{
    EnumerableSet.AddressSet storage pools = accountPools[_account];
    if(IERC20(_pool).balanceOf(_account) > 0){
      pools.add(_pool);
    }else{
      pools.remove(_pool);
    }
  }

  function addLiquidityNative(address _to,address _targetPool) external override nonReentrant returns(uint256){
    address nativeCurrency = dipxStorage.nativeCurrency();
    return _addLiquidity(nativeCurrency,_targetPool, _to);
  }

  function addLiquidity(address _collateralToken,address _targetPool,address _to) external override nonReentrant returns(uint256){
    return _addLiquidity(_collateralToken,_targetPool, _to);
  }

  function _handleAddLiquidity(address collateralToken,address targetPool,address to) private{
    if(dipxStorage.handler() != address(0)){
      IHandler(dipxStorage.handler()).afterAddLiquidity(collateralToken,targetPool,to);
    }
  }
  function _handleRemoveLiquidity(address pool,address receiveToken, address to) private{
    if(dipxStorage.handler() != address(0)){
      IHandler(dipxStorage.handler()).afterRemoveLiquidity(pool,receiveToken,to);
    }
  }

  function adjustForDecimals(uint256 _value, uint256 _decimalsDiv, uint256 _decimalsMul) public pure returns (uint256) {
    return _value * (10 ** _decimalsMul) / (10 ** _decimalsDiv);
  }

  function _addLiquidity(address _collateralToken,address _targetPool,address _to) private returns(uint256){
    require(_collateralToken != address(0) && !dipxStorage.greylistedTokens(_collateralToken), "Token blacklisted");
    require(!dipxStorage.greylist(_to) && !dipxStorage.greylist(msg.sender), "Account blacklisted");
    uint256 amountIn = _amountIn(_collateralToken);
    require(amountIn>0, "Insufficient amount");

    bool isNative = dipxStorage.isNativeCurrency(_collateralToken);
    uint8 tokenDecimals = isNative?dipxStorage.nativeCurrencyDecimals():IERC20Metadata(_collateralToken).decimals();
    uint256 liquidity;
    if(_targetPool == address(0) || !ILP(_targetPool).isMixed()){
      if(_targetPool != address(0)){
        require(ISingleLP(_targetPool).token() == _collateralToken, "Wrong token");
      }
      // single pool
      address lpToken = lpTokens[_collateralToken];
      if(lpToken == address(0)){
        string memory symbol = isNative?dipxStorage.nativeCurrencySymbol():IERC20Metadata(_collateralToken).symbol();
        string memory lpSymbol = string(bytes.concat(bytes("SLP-"), bytes(symbol)));
        
        lpToken = address(
          new SingleLP{
            salt:keccak256(abi.encodePacked(_collateralToken))
          }(_collateralToken,isNative, lpSymbol,tokenDecimals)
        );

        ISingleLP(lpToken).setMinter(dipxStorage.vault(), true);
        lpTokens[_collateralToken] = lpToken;
        lpEnable[lpToken] = true;
        isLpToken[lpToken] = true;

        emit CreatePool(msg.sender, _collateralToken, lpToken);
      }

      uint256 totalSupply = getSupplyWithPnl(lpToken, true, true);
      uint256 lpPrice = ISingleLP(lpToken).getPrice(address(dipxStorage), true, true);
      
      uint256 feePoint = dipxStorage.getBuyLpFeePoints(lpToken,_collateralToken, amountIn);
      uint256 amountInAfterfee = amountIn - amountIn * feePoint/dipxStorage.BASIS_POINT_DIVISOR();

      if(totalSupply>0){
        liquidity = amountInAfterfee * totalSupply / ISingleLP(lpToken).tokenReserve();
      }else{
        liquidity = amountInAfterfee;
      }

      _safeTransfer(_collateralToken, lpToken, amountIn);
      ISingleLP(lpToken).mint(_to, liquidity);

      updatePools(_to, lpToken);
      _handleAddLiquidity(_collateralToken,lpToken,_to);
      emit AddLiquidity(_to, _collateralToken, amountIn, lpToken, liquidity, lpPrice, 0);
    }else{
      // mixed pool
      require(isLpToken[_targetPool] && lpEnable[_targetPool] && _targetPool!=address(0), "Invalid pool");
      require(ILP(_targetPool).isMixed(), "Wrong pool");
      IMixedLP pool = IMixedLP(_targetPool);
      require(pool.isWhitelistedToken(_collateralToken), "Token not in whitelist");

      IVaultPriceFeed priceFeed = IVaultPriceFeed(dipxStorage.priceFeed());
      uint256 lpPrice = pool.getPrice(true, true, true);
      uint256 collateralPrice = priceFeed.getPrice(_collateralToken, false);

      {
      uint256 feePoint = dipxStorage.getBuyLpFeePoints(_targetPool,_collateralToken, amountIn);
      uint256 amountInAfterfee = amountIn - amountIn * feePoint/dipxStorage.BASIS_POINT_DIVISOR();
      amountInAfterfee = adjustForDecimals(amountInAfterfee,tokenDecimals,pool.decimals());
      liquidity = collateralPrice*amountInAfterfee/lpPrice;
      }
      _safeTransfer(_collateralToken, _targetPool, amountIn);
      pool.mint(_to, liquidity);
      pool.transferIn(_collateralToken, amountIn);
      
      updatePools(_to, _targetPool);
      _handleAddLiquidity(_collateralToken,_targetPool,_to);
      emit AddLiquidity(_to, _collateralToken, amountIn, _targetPool, liquidity, lpPrice, collateralPrice);
    }

    return liquidity;
  }

  function removeLiquidity(address _pool,address _receiveToken, address _to) external override nonReentrant returns(uint256){
    require(_pool != address(0) && lpEnable[_pool] && isLpToken[_pool], "Invalid pool");
    if(_receiveToken == address(0) || !ILP(_pool).isMixed()){
      return _removeLiquiditySingle(_pool, _to);
    }else{
      return _removeLiquidityMixed(_pool, _receiveToken, _to);
    }
  }

  function _removeLiquidityMixed(address _pool, address _receiveToken, address _to) private returns(uint256){
    require(ILP(_pool).isMixed(), "Wrong pool");
    IMixedLP pool = IMixedLP(_pool);
    uint256 liquidityIn = pool.balanceOf(address(this));
    require(pool.isTokenPooled(_receiveToken) && liquidityIn>0, "Invalid");

    uint8 tokenDecimals = dipxStorage.isNativeCurrency(_receiveToken)?dipxStorage.nativeCurrencyDecimals():IERC20Metadata(_receiveToken).decimals();

    uint256 supplyWithPnl = pool.getSupplyWithPnl(true, true);
    require(supplyWithPnl>=liquidityIn, "Insufficient");
    uint256 lpPrice = pool.getPrice(false, true, true);
    uint256 tokenPrice = IVaultPriceFeed(dipxStorage.priceFeed()).getPrice(_receiveToken,true);

    uint256 redemptionAmount = adjustForDecimals(lpPrice*liquidityIn, pool.decimals(), tokenDecimals)/tokenPrice;
    require(pool.tokenReserves(_receiveToken)>=redemptionAmount, "Insufficient token");

    if(supplyWithPnl!=liquidityIn){
      uint256 feePoint = dipxStorage.getSellLpFeePoints(_pool, _receiveToken, liquidityIn);
      redemptionAmount = redemptionAmount - redemptionAmount * feePoint/dipxStorage.BASIS_POINT_DIVISOR();
    }
    if(dipxStorage.isNativeCurrency(_receiveToken)){
      pool.withdrawEth(_to, redemptionAmount);
    }else{
      pool.withdrawToken(_receiveToken, _to, redemptionAmount);
    }
    pool.burn(liquidityIn);

    updatePools(_to, _pool);
    _handleRemoveLiquidity(_pool, _receiveToken, _to);
    emit RemoveLiquidity(_to, _pool, _receiveToken, liquidityIn, redemptionAmount,lpPrice,tokenPrice);
    return redemptionAmount;
  }

  function _removeLiquiditySingle(address _lpToken,address _to) private returns(uint256){
    require(_lpToken != address(0) && !ILP(_lpToken).isMixed(), "Invalid pool");
    uint256 liquidityIn = ISingleLP(_lpToken).balanceOf(address(this));

    uint256 totalSupply = getSupplyWithPnl(_lpToken, true, true);
    require(totalSupply>=liquidityIn && liquidityIn>0, "Insufficient");
    address collateralToken = ISingleLP(_lpToken).token();
    uint256 lpPrice = ISingleLP(_lpToken).getPrice(address(dipxStorage), true, true);
    uint256 collateralOut = liquidityIn * ISingleLP(_lpToken).tokenReserve() / totalSupply;

    ISingleLP(_lpToken).burn(liquidityIn);
    ISingleLP(_lpToken).withdraw(_to, collateralOut);

    updatePools(_to, _lpToken);
    _handleRemoveLiquidity(_lpToken, collateralToken, _to);
    emit RemoveLiquidity(_to, _lpToken, collateralToken, liquidityIn, collateralOut,lpPrice,0);
    return collateralOut;
  }
}
