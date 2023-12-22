// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./TransferHelper.sol";
import "./IERC20Metadata.sol";
import "./ILpManager.sol";
import "./IRouter.sol";
import "./IDipxStorage.sol";
import "./IPositionManager.sol";
import "./IVaultPriceFeed.sol";
import "./IPythPriceFeed.sol";
import "./IReferral.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract Router is IRouter,Initializable,OwnableUpgradeable,ReentrancyGuardUpgradeable{
  address public dipxStorage;

  mapping(address => bool) public plugins;

  function initialize(address _dipxStorage) public initializer {
    __Ownable_init();
    __ReentrancyGuard_init();
    dipxStorage = _dipxStorage;
  }

  receive() external payable{}

  function setDipxStorage(address _dipxStorage) external override onlyOwner{
    dipxStorage = _dipxStorage;
  }

  function getLpManager() public view returns(address){
    return IDipxStorage(dipxStorage).lpManager();
  }
  function getPositionManager() public view returns(address){
    return IDipxStorage(dipxStorage).positionManager();
  }
  function getReferral() public view returns(address){
    return IDipxStorage(dipxStorage).referral();
  }
  function getPricefeed() public view returns(address){
    return IDipxStorage(dipxStorage).priceFeed();
  }
  function isLpToken(address _token) public override view returns(bool,bool) {
    address lpManager = getLpManager();
    bool isLp = ILpManager(lpManager).isLpToken(_token);
    bool enable = ILpManager(lpManager).lpEnable(_token);
    return (isLp, enable);
  }
  function getLpToken(address collateralToken) public override view returns(address){
    address lpManager = getLpManager();
    return ILpManager(lpManager).lpTokens(collateralToken);
  }
  function getPoolPrice(address _pool,bool _maximise,bool _includeProfit,bool _includeLoss) public override view returns(uint256){
    address lpManager = getLpManager();
    if(ILpManager(lpManager).isLpToken(_pool)){
      return ILpManager(lpManager).getPoolPrice(_pool, _maximise, _includeProfit, _includeLoss);
    }else{
      uint256 pricePrecision = 10**IVaultPriceFeed(getPricefeed()).decimals();
      return 1 * pricePrecision;
    }
  }

  function getAccountPools(address _account) public view returns(Liquidity[] memory){
    ILpManager lpManager = ILpManager(getLpManager());
    uint256 len = lpManager.getAccountPoolLength(_account);
    uint256 count = 0;
    for (uint256 i = 0; i < len; i++) {
      address pool = lpManager.getAccountPoolAt(_account, i);
      if(IERC20Metadata(pool).balanceOf(_account) > 0){
        count = count + 1;
      }
    }
    Liquidity[] memory datas = new Liquidity[](count);
    uint256 index = 0;
    for (uint256 i = 0; i < len; i++) {
      address pool = lpManager.getAccountPoolAt(_account, i);
      IERC20Metadata erc20 = IERC20Metadata(pool);
      uint256 balance = erc20.balanceOf(_account);
      if(balance > 0){
        datas[index] = Liquidity(
                        pool,
                        erc20.name(),
                        erc20.symbol(),
                        erc20.decimals(),
                        balance
                      );
        index = index + 1;
      }
    }

    return datas;
  }

  function getAccountPositions(address _account) public view returns(IPositionManager.Position[] memory){
    IPositionManager pm = IPositionManager(getPositionManager());
    uint256 len = pm.getPositionKeyLength(_account);
    IPositionManager.Position[] memory positions = new IPositionManager.Position[](len);
    for (uint256 i = 0; i < len; i++) {
      bytes32 key = pm.getPositionKeyAt(_account,i);
      positions[i] = pm.getPositionByKey(key);
    }
    return positions;
  }

  function _updatePrice(bytes[] memory _priceUpdateData) private{
    if(_priceUpdateData.length == 0){
      return;
    }

    IVaultPriceFeed pricefeed = IVaultPriceFeed(getPricefeed());
    IPythPriceFeed pythPricefeed = IPythPriceFeed(pricefeed.pythPriceFeed());
    pythPricefeed.updatePriceFeeds(_priceUpdateData);
  }

  function addLiquidityNative(
    address _targetPool,
    uint256 _amountIn, 
    address _to,
    uint256 _price,
    address _referrer,
    bytes[] memory _priceUpdateData
  ) external nonReentrant payable override returns(uint256){
    require(_amountIn>0 && _amountIn==msg.value, "Insufficient token");
    address pool = _targetPool;
    address lpManager = getLpManager();
    if(pool == address(0)){
      pool = ILpManager(lpManager).lpTokens(IDipxStorage(dipxStorage).nativeCurrency());
    }
    _setReferrer(msg.sender, _referrer);
    _updatePrice(_priceUpdateData);
    uint256 currentPrice = getPoolPrice(pool, true, true, true);
    require(_price >= currentPrice, "Pool price higher than limit");
    TransferHelper.safeTransferETH(lpManager, _amountIn);
    return ILpManager(lpManager).addLiquidityNative(_to,_targetPool);
  }

  function addLiquidity(
    address _collateralToken,
    address _targetPool,
    uint256 _amount,
    address _to,
    uint256 _price,
    address _referrer,
    bytes[] memory _priceUpdateData
  ) external override nonReentrant returns(uint256){
    address pool = _targetPool;
    address lpManager = getLpManager();
    if(pool == address(0)){
      pool = ILpManager(lpManager).lpTokens(_collateralToken);
    }
    _setReferrer(msg.sender, _referrer);
    _updatePrice(_priceUpdateData);
    uint256 currentPrice = getPoolPrice(pool, true, true, true);
    require(_price >= currentPrice, "Pool price higher than limit");

    require(_amount>0, "Insufficient amount");
    TransferHelper.safeTransferFrom(_collateralToken, msg.sender, lpManager, _amount);
    return ILpManager(lpManager).addLiquidity(_collateralToken,_targetPool, _to);
  }

  function removeLiquidity(
    address _lpToken,
    address _receiveToken, 
    uint256 _liquidity,
    address _to,
    uint256 _price,
    address _referrer,
    bytes[] memory _priceUpdateData
  ) external override nonReentrant returns(uint256){
    _updatePrice(_priceUpdateData);

    uint256 currentPrice = getPoolPrice(_lpToken, false, true, true);
    require(_price <= currentPrice, "Pool price lower than limit");
    require(_liquidity>0, "Insufficient liquidity");

    _setReferrer(msg.sender, _referrer);
    address lpManager = getLpManager();
    TransferHelper.safeTransferFrom(_lpToken, msg.sender, lpManager, _liquidity);
    return ILpManager(lpManager).removeLiquidity(_lpToken, _receiveToken, _to);
  }

  function getPoolLiqFee(address _pool) external view override returns(uint256){
    return IDipxStorage(dipxStorage).getTokenGasFee(_pool);
  }

  function addPlugin(address _plugin) external override onlyOwner {
    plugins[_plugin] = true;
  }

  function removePlugin(address _plugin) external override onlyOwner {
    plugins[_plugin] = false;
  }

  function _validatePlugin(address _plugin) private view{
    require(plugins[_plugin], "PositionRouter: invalid plugin");
  }

  function _setReferrer(address _account, address _referrer) private{
    if(_referrer != address(0)){
      address referral = getReferral();
      if(referral != address(0)){
        (
            address preReferrer,
            /*uint256 totalRebate*/,
            /*uint256 discountShare*/
        ) = IReferral(referral).getTraderReferralInfo(_account);
        if(preReferrer == address(0)){
          IReferral(referral).setTraderReferral(_account, _referrer);
        }
      }
    }
  }

  function increasePosition(
    address _indexToken,
    address _collateralToken,
    uint256 _amountIn,
    uint256 _sizeDelta,
    uint256 _price,
    bool _isLong,
    address _referrer,
    bytes[] memory _priceUpdateData
  ) external override payable nonReentrant{
    _updatePrice(_priceUpdateData);

    IPositionManager positionManager = IPositionManager(getPositionManager());
    if(_isLong){
      require(positionManager.getMaxPrice(_indexToken)<=_price, "PositionRouter: mark price higher than limit");
    }else{
      require(positionManager.getMinPrice(_indexToken)>=_price, "PositionRouter: mark price lower than limit");
    }
    _setReferrer(msg.sender, _referrer);
    TransferHelper.safeTransferFrom(_collateralToken, msg.sender, address(positionManager), _amountIn);
    _increasePosition(msg.sender, _indexToken, _collateralToken, _sizeDelta, _isLong);
  }

  function pluginIncreasePosition(
    address _account,
    address _indexToken,
    address _collateralToken,
    uint256 _amountIn,
    uint256 _sizeDelta,
    bool _isLong
  ) external override payable nonReentrant{
    _validatePlugin(msg.sender);
    TransferHelper.safeTransfer(_collateralToken, IDipxStorage(dipxStorage).positionManager(), _amountIn);
    _increasePosition(_account, _indexToken, _collateralToken, _sizeDelta, _isLong);
  }

  function decreasePosition(
    address _indexToken, 
    address _collateralToken, 
    uint256 _sizeDelta, 
    uint256 _collateralDelta, 
    bool _isLong, 
    address _receiver,
    uint256 _price,
    address _referrer,
    bytes[] memory _priceUpdateData
  )external override payable nonReentrant returns(uint256){
    _updatePrice(_priceUpdateData);

    IPositionManager positionManager = IPositionManager(getPositionManager());
    if(_isLong){
      require(positionManager.getMinPrice(_indexToken)>=_price, "PositionRouter: mark price lower than limit");
    }else{
      require(positionManager.getMaxPrice(_indexToken)<=_price, "PositionRouter: mark price high than limit");
    }
    _setReferrer(msg.sender, _referrer);
    return _decreasePosition(msg.sender, _indexToken, _collateralToken, _sizeDelta, _collateralDelta, _isLong, _receiver);
  }

  function pluginDecreasePosition(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    uint256 _sizeDelta, 
    uint256 _collateralDelta, 
    bool _isLong, 
    address _receiver
  )external override payable nonReentrant returns(uint256){
    _validatePlugin(msg.sender);
    return _decreasePosition(_account, _indexToken, _collateralToken, _sizeDelta, _collateralDelta, _isLong, _receiver);
  }

  function _decreasePosition(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    uint256 _sizeDelta, 
    uint256 _collateralDelta, 
    bool _isLong, 
    address _receiver
  )private returns(uint256){
    IPositionManager positionManager = IPositionManager(getPositionManager());
    (uint256 liquidationState, ) = positionManager.validateLiquidation(_account, _collateralToken, _indexToken, _isLong, false);
    if(liquidationState==0){
      uint256 tokenOutAfterFee = positionManager.decreasePosition{value:msg.value}(_account, _indexToken, _collateralToken, _sizeDelta, _collateralDelta, _isLong, _receiver);
      return tokenOutAfterFee;
    }else{
      positionManager.liquidatePosition(
        _account, 
        _indexToken, 
        _collateralToken, 
        _isLong,
        msg.sender
      );
      if(msg.value>0){
        TransferHelper.safeTransferETH(msg.sender, msg.value);
      }
      return 0;
    }
  }

  function _increasePosition(
    address _account,
    address _indexToken,
    address _collateralToken,
    uint256 _sizeDelta,
    bool _isLong
  ) private{
    IPositionManager positionManager = IPositionManager(getPositionManager());
    positionManager.increasePosition{value:msg.value}(_account, _indexToken, _collateralToken, _sizeDelta, _isLong);
  }

  function liquidatePosition(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    bool _isLong,
    address _feeReceiver,
    bytes[] memory _priceUpdateData
  ) external override{
    _updatePrice(_priceUpdateData);
    IPositionManager positionManager = IPositionManager(getPositionManager());
    positionManager.liquidatePosition(
      _account, 
      _indexToken, 
      _collateralToken, 
      _isLong,
      _feeReceiver
    );
  }

  function withdrawETH(address _receiver, uint256 _amountOut) external onlyOwner {
    TransferHelper.safeTransferETH(_receiver, _amountOut);
  }
}
