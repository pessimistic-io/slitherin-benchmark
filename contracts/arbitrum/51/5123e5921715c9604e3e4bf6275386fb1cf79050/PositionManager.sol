// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./IVaultPriceFeed.sol";
import "./IPositionManager.sol";
import "./ILpManager.sol";
import "./IVault.sol";
import "./IDipxStorage.sol";
import "./IMintableERC20.sol";
import "./IHandler.sol";
import "./IReferral.sol";
import "./TransferHelper.sol";
import "./EnumerableSet.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract PositionManager is Initializable,OwnableUpgradeable,ReentrancyGuardUpgradeable,IPositionManager{
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;

  EnumerableSet.AddressSet private allIndexTokens;
  mapping(address => bool) public allCollateralsAccept;
  mapping(address => mapping(address => bool)) public indexAcceptCollaterals;

  uint256 public constant BASIS_POINTS_DIVISOR = 1000000;

  mapping (bytes32 => Position) public positions;

  IDipxStorage public dipxStorage;
  mapping (address => uint256) public override globalBorrowAmounts;

  mapping (address => EnumerableSet.Bytes32Set) private accountPositionKeys;

  event IncreasePosition(
    address account,
    address collateralToken,
    address indexToken,
    uint256 collateralDelta,
    uint256 sizeDelta,
    bool isLong,
    uint256 entryFundingRate,
    int256 fundingFactor,
    uint256 price,
    uint256 fee
  );
  event DecreasePosition(
    address account,
    address collateralToken,
    address indexToken,
    uint256 collateralDelta,
    uint256 sizeDelta,
    bool isLong,
    uint256 entryFundingRate,
    int256 fundingFactor,
    uint256 price,
    address receiver,
    uint256 fee
  );
  event LiquidatePosition(
      address account,
      address collateralToken,
      address indexToken,
      bool isLong,
      uint256 size,
      uint256 collateral,
      uint256 markPrice,
      uint256 liqFee,
      uint256 marginFee
  );
  event UpdatePosition(
      address account,
      address collateralToken,
      address indexToken,
      bool isLong,
      uint256 size,
      uint256 collateral,
      uint256 averagePrice,
      uint256 entryFundingRate,
      int256 fundingFactor,
      int256 realisedPnl,
      uint256 markPrice,
      uint256 averagePoolPrice
  );
  event ClosePosition(
      address account,
      address collateralToken,
      address indexToken,
      bool isLong,
      uint256 size,
      uint256 collateral,
      uint256 averagePrice,
      uint256 entryFundingRate,
      int256 fundingFactor,
      uint256 averagePoolPrice,
      int256 realisedPnl
  );

  constructor(){
  }

  function initialize(
    address[] memory _indexTokens,
    address _dipxStorage
  ) public initializer {
    __Ownable_init();
    __ReentrancyGuard_init();

    dipxStorage = IDipxStorage(_dipxStorage);
    for (uint256 i = 0; i < _indexTokens.length; i++) {
      allIndexTokens.add(_indexTokens[i]);
      allCollateralsAccept[_indexTokens[i]] = true;
    }
  }

  receive() external payable{}

  function getPositionKeyLength(address _account) public override view returns(uint256){
    return accountPositionKeys[_account].length();
  }
  function getPositionKeyAt(address _account, uint256 _index) public override view returns(bytes32){
    return accountPositionKeys[_account].at(_index);
  }

  function enableIndexToken(address _indexToken,bool _enable) external override onlyOwner {
    if(_enable){
      allIndexTokens.add(_indexToken);
    }else{
      allIndexTokens.remove(_indexToken);
    }
  }

  function toggleCollateralsAccept(address _indexToken) external override onlyOwner {
    allCollateralsAccept[_indexToken] = !allCollateralsAccept[_indexToken];
  }

  function addIndexCollaterals(address _indexToken,address[] memory _collateralTokens) external override onlyOwner {
    _validateIndexToken(_indexToken);

    for (uint256 i = 0; i < _collateralTokens.length; i++) {
      indexAcceptCollaterals[_indexToken][_collateralTokens[i]] = true;
    }
  }

  function removeIndexCollaterals(address _indexToken,address[] memory _collateralTokens) external override onlyOwner {
    _validateIndexToken(_indexToken);

    for (uint256 i = 0; i < _collateralTokens.length; i++) {
      indexAcceptCollaterals[_indexToken][_collateralTokens[i]] = false;
    }
  }

  function indexTokenLength() public override view returns(uint256){
    return allIndexTokens.length();
  }
  function indexTokenAt(uint256 _at) public override view returns(address){
    return allIndexTokens.at(_at);
  }

  function setDipxStorage(address _dipxStorage) external override onlyOwner{
    dipxStorage = IDipxStorage(_dipxStorage);
  }

  function getPositionByKey(bytes32 key) public view override returns(Position memory){
    return positions[key];
  }

  function getPosition(
    address _account,address _indexToken, address _collateralToken, bool _isLong
  ) public view override returns(Position memory){
    bytes32 key = getPositionKey(_account, _indexToken, _collateralToken, _isLong);
    return getPositionByKey(key);
  }
  function getPositionKey(address _account, address _indexToken, address _collateralToken, bool _isLong) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(
      _account,
      _indexToken,
      _collateralToken,
      _isLong
    ));
  }

  function getPositionLeverage(address _account, address _indexToken, address _collateralToken, bool _isLong) public view override returns (uint256) {
    bytes32 key = getPositionKey(_account, _indexToken, _collateralToken, _isLong);
    require(positions[key].collateral > 0, "PositionManager: Collateral error");
    return positions[key].size * BASIS_POINTS_DIVISOR / positions[key].collateral;
  }

  function increasePosition(
    address _account,
    address _indexToken, 
    address _collateralToken,
    uint256 _sizeDelta,
    bool _isLong
  ) external payable override nonReentrant{
    require(!dipxStorage.greylist(_account), "PositionManager: account in blacklist");
    _validateIncrease(_collateralToken);
    _validatefee(_collateralToken);
    _validateRouter(_account);
    _validateIndexToken(_indexToken);
    _validateCollateralToken(_collateralToken);
    _validateUnderlying(_indexToken, _collateralToken);

    uint256 amountIn = IERC20(_collateralToken).balanceOf(address(this));
    if(dipxStorage.handler() != address(0)){
      IHandler(dipxStorage.handler()).beforeIncreasePosition(
        _account,
        _indexToken, 
        _collateralToken,
        _sizeDelta,
        amountIn,
        _isLong
      );
    }

    updateCumulativeFundingRate(_indexToken, _collateralToken);

    if(amountIn > 0){
      TransferHelper.safeTransfer(_collateralToken, dipxStorage.vault(), amountIn);
    }
    require(_sizeDelta>0 || amountIn>0, "PositionManager: size or amountIn invalid");

    _decreaseBorrowed(_account, _indexToken, _collateralToken, _isLong);

    bytes32 key = getPositionKey(_account, _indexToken, _collateralToken, _isLong);
    Position storage position = positions[key];
    position.account = _account;
    position.indexToken = _indexToken;
    position.collateralToken = _collateralToken;
    position.isLong = _isLong;
    Position storage globalPosition = positions[getPositionKey(address(0), _indexToken, _collateralToken, _isLong)];
    globalPosition.account = address(0);
    globalPosition.indexToken = _indexToken;
    globalPosition.collateralToken = _collateralToken;
    globalPosition.isLong = _isLong;


    uint256 price = _isLong ? getMaxPrice(_indexToken) : getMinPrice(_indexToken);
    if(_sizeDelta>0){
      uint256 poolPrice = ILpManager(dipxStorage.lpManager()).getPoolPrice(_collateralToken, true, true, true);
      if (position.size == 0) {
        position.averagePrice = price;
        position.averagePoolPrice = poolPrice;
      }else{
        if (position.size > 0) {
          position.averagePrice = getNextAveragePrice(_indexToken, position.size, position.averagePrice, _isLong, price, _sizeDelta, position.lastIncreasedTime);
          position.averagePoolPrice = getNextPoolAveragePrice(position.size, position.averagePoolPrice, poolPrice, _sizeDelta);
        }
      }

      if(globalPosition.size == 0){
        globalPosition.averagePrice = price;
        globalPosition.averagePoolPrice = poolPrice;
      }else{
        if(_sizeDelta > 0){
          globalPosition.averagePrice = getNextAveragePrice(_indexToken, globalPosition.size, globalPosition.averagePrice, _isLong, price, _sizeDelta, globalPosition.lastIncreasedTime);
          globalPosition.averagePoolPrice = getNextPoolAveragePrice(globalPosition.size, globalPosition.averagePoolPrice, poolPrice, _sizeDelta);
        }
      }
    }

    uint256 fee = _calculateFee(
      _calculatePositionFee(_account, _indexToken, _collateralToken, _sizeDelta), 
      _calculateFundingFee(_account, _indexToken, _collateralToken, _isLong)
    );
    
    position.collateral = position.collateral + amountIn;
    require(position.collateral > fee, "PositionManager: fee exceed collateral");
    position.collateral = position.collateral - fee;
    position.size = position.size + _sizeDelta;
    position.lastIncreasedTime = block.timestamp;
    IDipxStorage.FeeRate memory rate = dipxStorage.cumulativeFundingRates(_indexToken, _collateralToken);
    position.entryFundingRate = _isLong?rate.longRate:rate.shortRate;

    _validateLeverage(_collateralToken, position.size, position.collateral);

    _validateLiquidation(_account, _collateralToken, _indexToken, _isLong, true);

    globalPosition.collateral = globalPosition.collateral + amountIn - fee;
    globalPosition.size = globalPosition.size + _sizeDelta;
    globalPosition.lastIncreasedTime = block.timestamp;

    _collectFee(_account, _collateralToken, fee);
    _increaseBorrowed(_account, _indexToken, _collateralToken, _isLong);
    _updatePositionKeys(_account, _indexToken, _collateralToken, _isLong);
    _emitIncreaseEvent(_account, _indexToken, _collateralToken, _sizeDelta, amountIn, _isLong,fee);
  }

  function _updatePositionKeys(
    address _account,
    address _indexToken, 
    address _collateralToken,
    bool _isLong
  ) private {
    bytes32 key = getPositionKey(_account, _indexToken, _collateralToken, _isLong);
    EnumerableSet.Bytes32Set storage keys = accountPositionKeys[_account];
    if(positions[key].size > 0){
      keys.add(key);
    }else{
      keys.remove(key);
    }
  }
  
  function _emitIncreaseEvent(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    uint256 _sizeDelta, 
    uint256 _collateralDelta, 
    bool _isLong, 
    uint256 _fee
  ) private {
    uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
    bytes32 key = getPositionKey(_account, _indexToken, _collateralToken, _isLong);
    Position memory position = positions[key];

    if(dipxStorage.handler() != address(0)){
      IHandler(dipxStorage.handler()).afterIncreasePosition(
        _account,
        _indexToken, 
        _collateralToken,
        _sizeDelta,
        _collateralDelta,
        _isLong,
        price,
        _fee
      );
    }
    emit IncreasePosition(
      _account, 
      _collateralToken, 
      _indexToken, 
      _collateralDelta, 
      _sizeDelta, 
      _isLong, 
      position.entryFundingRate, 
      position.fundingFactor, 
      price,
      _fee
    );
    
    emit UpdatePosition(
      _account, 
      _collateralToken, 
      _indexToken, 
      _isLong, 
      position.size, 
      position.collateral, 
      position.averagePrice, 
      position.entryFundingRate, 
      position.fundingFactor,
      position.realisedPnl, 
      price,
      position.averagePoolPrice
    );
  }

  function decreasePosition(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    uint256 _sizeDelta, 
    uint256 _collateralDelta, 
    bool _isLong, 
    address _receiver
  ) external payable override nonReentrant returns(uint256){
    _validateDecrease(_collateralToken);
    _validatefee(_collateralToken);
    _validateRouter(_account);
    _validateIndexToken(_indexToken);
    _validateCollateralToken(_collateralToken);

    if(dipxStorage.handler() != address(0)){
      IHandler(dipxStorage.handler()).beforeDecreasePosition(
        _account,
        _indexToken, 
        _collateralToken, 
        _sizeDelta, 
        _collateralDelta, 
        _isLong, 
        _receiver
      );
    }
    return _decreasePosition(_account, _indexToken, _collateralToken, _sizeDelta, _collateralDelta, _isLong, _receiver);
  }

  function liquidatePosition(
    address _account, 
    address _indexToken, 
    address _collateralToken, 
    bool _isLong,
    address _feeReceiver
  ) external override nonReentrant {
    _validateLiquidate(_collateralToken);
    _validateIndexToken(_indexToken);
    _validateCollateralToken(_collateralToken);
    require(dipxStorage.isLiquidator(msg.sender), "PositionManager: invalid liquidator");
    if(dipxStorage.handler() != address(0)){
      IHandler(dipxStorage.handler()).beforeLiquidatePosition(
        _account, 
        _indexToken, 
        _collateralToken, 
        _isLong,
        _feeReceiver
      );
    }

    bytes32 key = getPositionKey(_account, _indexToken, _collateralToken, _isLong);
    Position memory position = positions[key];
    require(position.size > 0, "PositionManager: position error");

    updateCumulativeFundingRate(_indexToken, _collateralToken);

    (uint256 liquidationState, uint256 marginFees) = _validateLiquidation(_account, _collateralToken, _indexToken, _isLong, false);
    require(liquidationState>0, "PositionManager: liquidate state error");
    if (liquidationState == 2) {
      // max leverage exceeded but there is collateral remaining after deducting losses so decreasePosition instead
      _decreasePosition(_account, _indexToken, _collateralToken, position.size, 0, _isLong, _account);
      return;
    }

    _decreaseBorrowed(_account, _indexToken, _collateralToken, _isLong);

    if(position.collateral<marginFees){
      marginFees = position.collateral;
    }
    _collectFee(_account, _collateralToken, marginFees);
    if(position.collateral>marginFees){
      IVault(dipxStorage.vault()).burn(_collateralToken, position.collateral-marginFees);
    }

    uint256 liqFee = dipxStorage.getTokenGasFee(_collateralToken);
    if(liqFee>0){
      TransferHelper.safeTransferETH(_feeReceiver, liqFee);
    }

    uint256 markPrice = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
    if(dipxStorage.handler() != address(0)){
      IHandler(dipxStorage.handler()).afterLiquidatePosition(
        _account, 
        _indexToken, 
        _collateralToken, 
        _isLong,
        _feeReceiver,
        position.size, 
        position.collateral, 
        markPrice, 
        liqFee,
        marginFees
      );
    }
    emit LiquidatePosition(_account, _collateralToken, _indexToken, _isLong, position.size, position.collateral, markPrice, liqFee, marginFees);

    Position storage globalPosition = positions[getPositionKey(address(0),_indexToken, _collateralToken, _isLong)];
    globalPosition.collateral = globalPosition.collateral - position.collateral;
    globalPosition.size = globalPosition.size - position.size;
    delete positions[key];

    _updatePositionKeys(_account, _indexToken, _collateralToken, _isLong);
  }

  function calculateUnrealisedPnl(
    address _indexToken,
    address _collateralToken
  ) public view override returns(bool, uint256){
    Position memory longPosition = getPosition(address(0), _indexToken, _collateralToken, true);
    Position memory shortPosition = getPosition(address(0), _indexToken, _collateralToken, false);
    (bool hasLongProfit,uint256 longDelta) = getDelta(_indexToken, longPosition.size, longPosition.averagePrice, true, 0);
    (bool hasShortProfit,uint256 shortDelta) = getDelta(_indexToken, shortPosition.size, shortPosition.averagePrice, false, 0);
    bool hasProfit;
    uint256 pnl;
    if(!hasLongProfit){
      longDelta = longDelta>longPosition.collateral?longPosition.collateral:longDelta;
    }
    if(!hasShortProfit){
      shortDelta = shortDelta>shortPosition.collateral?shortPosition.collateral:shortDelta;
    }
    if(hasLongProfit == hasShortProfit){
      hasProfit = hasLongProfit;
      pnl = longDelta + shortDelta;
    }else{
      if(longDelta > shortDelta){
        hasProfit = hasLongProfit;
        pnl = longDelta - shortDelta;
      }else{
        hasProfit = hasShortProfit;
        pnl = shortDelta - longDelta;
      }
    }

    return (hasProfit, pnl);
  }

  function _decreasePosition(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    uint256 _sizeDelta, 
    uint256 _collateralDelta, 
    bool _isLong, 
    address _receiver
  ) private returns(uint256){
    updateCumulativeFundingRate(_indexToken, _collateralToken);
    _decreaseBorrowed(_account, _indexToken, _collateralToken, _isLong);

    bytes32 key = getPositionKey(_account, _indexToken, _collateralToken, _isLong);
    Position storage position = positions[key];
    Position storage globalPosition = positions[getPositionKey(address(0), _indexToken, _collateralToken, _isLong)];
    require(position.size > 0, "PositionManager: position not found");
    require(position.size >= _sizeDelta, "PositionManager: size < _sizeDelta");
    require(position.collateral >= _collateralDelta, "PositionManager: collateral < _collateralDelta");

    uint256 collateral = position.collateral;

    (, uint256 tokenOutAfterFee, uint256 fee) = _reduceCollateral(_account, _indexToken, _collateralToken, _sizeDelta, _collateralDelta, _isLong);
    position.size = position.size - _sizeDelta;
    globalPosition.size = globalPosition.size - _sizeDelta;
    globalPosition.collateral = globalPosition.collateral + position.collateral - collateral;
    if (position.size > 0) {
      if(_isLong){
        IDipxStorage.FeeRate memory rate = dipxStorage.cumulativeFundingRates(_indexToken, _collateralToken);
        position.entryFundingRate = rate.longRate;
      }else{
        IDipxStorage.FeeRate memory rate = dipxStorage.cumulativeFundingRates(_indexToken, _collateralToken);
        position.entryFundingRate = rate.shortRate;
      }
      
      _validateLeverage(_collateralToken, position.size, position.collateral);
      _validateLiquidation(_account, _collateralToken, _indexToken, _isLong, true);
    }
    
    if(tokenOutAfterFee > 0){
      IVault(dipxStorage.vault()).transferOut(_collateralToken, _receiver, tokenOutAfterFee);
    }

    _emitDecreaseEvent(_account, _indexToken, _collateralToken, _sizeDelta, _collateralDelta, _isLong, _receiver, fee);

    if(position.size == 0 || position.collateral == 0){
      emit ClosePosition(
        _account, 
        _collateralToken, 
        _indexToken, 
        _isLong, 
        _sizeDelta, 
        collateral, 
        position.averagePrice, 
        position.entryFundingRate, 
        position.fundingFactor, 
        position.averagePoolPrice, 
        position.realisedPnl
      );
      delete positions[key];
    }
    _updatePositionKeys(_account, _indexToken, _collateralToken, _isLong);
    _increaseBorrowed(_account, _indexToken, _collateralToken, _isLong);
    return tokenOutAfterFee;
  }

  function _emitDecreaseEvent(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    uint256 _sizeDelta, 
    uint256 _collateralDelta, 
    bool _isLong, 
    address _receiver,
    uint256 _fee
  ) private {
    uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
    Position memory position = getPosition(_account, _indexToken, _collateralToken, _isLong);

    if(dipxStorage.handler() != address(0)){
      IHandler(dipxStorage.handler()).afterDecreasePosition(
        _account,
        _indexToken, 
        _collateralToken, 
        _sizeDelta, 
        _collateralDelta, 
        _isLong, 
        _receiver,
        _fee
      );
    }
    emit DecreasePosition(
      _account, 
      _collateralToken, 
      _indexToken, 
      _collateralDelta, 
      _sizeDelta, 
      _isLong, 
      position.entryFundingRate, 
      position.fundingFactor,
      price, 
      _receiver,
      _fee
    );
    emit UpdatePosition(
      _account, 
      _collateralToken, 
      _indexToken, 
      _isLong, 
      position.size, 
      position.collateral, 
      position.averagePrice, 
      position.entryFundingRate, 
      position.fundingFactor,
      position.realisedPnl, 
      price,
      position.averagePoolPrice
    );
  }

  function _reduceCollateral(
    address _account, 
    address _indexToken, 
    address _collateralToken, 
    uint256 _sizeDelta, 
    uint256 _collateralDelta, 
    bool _isLong
  ) private returns(uint256,uint256,uint256){
    bytes32 key = getPositionKey(_account, _indexToken, _collateralToken, _isLong);
    Position storage position = positions[key];
    
    uint256 fee;
    {
    int256 fundingFees = _calculateFundingFee(_account, _indexToken, _collateralToken, _isLong);
    uint256 positionFees = _calculatePositionFee(_account, _indexToken, _collateralToken, _sizeDelta);
    fee = _calculateFee(positionFees, fundingFees);
    }

    uint256 tokenOut;
    {
      (bool hasProfit, uint256 delta) = getDelta(_indexToken, position.size, position.averagePrice, _isLong, position.lastIncreasedTime);
      uint256 adjustedDelta = _sizeDelta * delta / position.size;

      if (hasProfit && adjustedDelta > 0) {
        tokenOut = adjustedDelta;
        position.realisedPnl = position.realisedPnl + int256(adjustedDelta);
        IVault(dipxStorage.vault()).mint(_collateralToken, adjustedDelta);
      }

      if(!hasProfit && adjustedDelta > 0){
        position.collateral = position.collateral - adjustedDelta;
        position.realisedPnl = position.realisedPnl - int256(adjustedDelta);
        IVault(dipxStorage.vault()).burn(_collateralToken, adjustedDelta);
      }
    }
    
    if (_collateralDelta > 0) {
      tokenOut = tokenOut + _collateralDelta;
      position.collateral = position.collateral - _collateralDelta;
    }

    if (position.size == _sizeDelta) {
      tokenOut = tokenOut + position.collateral;
      position.collateral = 0;
    }
    
    uint256 tokenOutAfterFee = tokenOut;
    if (tokenOut > fee) {
      tokenOutAfterFee = tokenOut - fee;
    } else {
      position.collateral = position.collateral - fee;
    }

    _collectFee(_account, _collateralToken, fee);

    return (tokenOut, tokenOutAfterFee, fee);
  }

  function _validateIndexToken(address _indexToken) private view{
    require(allIndexTokens.contains(_indexToken), "INVALID INDEX TOKEN");
  }
  function _validateCollateralToken(address _collateralToken) private view{
    ILpManager lpManager = ILpManager(dipxStorage.lpManager());
    require(lpManager.isLpToken(_collateralToken), "PositionManager: invalid collateralToken");
    require(lpManager.lpEnable(_collateralToken), "PositionManager: invalid collateralToken");
  }
  function _validateUnderlying(address _indexToken,address _collateralToken) private view{
    if(allCollateralsAccept[_indexToken]){
      return;
    }
    require(indexAcceptCollaterals[_indexToken][_collateralToken], "PositionManager: invalid index/collateral");
  }

  function _collectFee(address _account, address _token, uint256 _amount) private{
    if(_amount>0){
      address referral = dipxStorage.referral();
      uint256 amountAfterRebate = _amount;
      IVault vault = IVault(dipxStorage.vault());
      if(referral != address(0)){
        uint256 rebateAmount = IReferral(referral).calculateRebateAmount(_account, _amount);
        if(rebateAmount>0){
          amountAfterRebate = amountAfterRebate - rebateAmount;
          vault.transferOut(_token, referral, rebateAmount);
          IReferral(referral).rebate(_token, _account, rebateAmount);
        }
      }
      
      uint256 feeToLpAmount = dipxStorage.getLpPositionFee(_token, amountAfterRebate);
      if(feeToLpAmount>0){
        vault.burn(_token, feeToLpAmount);
      }
      if(amountAfterRebate>feeToLpAmount){
        vault.transferOut(_token, dipxStorage.feeTo(), amountAfterRebate-feeToLpAmount);
      }
    }
  }
  
  function _calculateFundingFee(address _account, address _indexToken, address _collateralToken, bool _isLong) private view returns(int256){
    return dipxStorage.getFundingFee(_account, _indexToken, _collateralToken, _isLong);
  }
  function _calculatePositionFee(address _account,address _indexToken,address _collateralToken, uint256 _tradeAmount) private view returns(uint256) {
    return dipxStorage.getPositionFee(_account,_indexToken,_collateralToken, _tradeAmount);
  }

  function getNextPoolAveragePrice(uint256 _size, uint256 _averagePrice,uint256 _nextPrice, uint256 _sizeDelta) private pure returns(uint256){
    return (_nextPrice*_sizeDelta+_averagePrice*_size)/(_size+_sizeDelta);
  }

  function getNextAveragePrice(
    address /*_indexToken*/, 
    uint256 _size, 
    uint256 _averagePrice, 
    bool /*_isLong*/, 
    uint256 _nextPrice, 
    uint256 _sizeDelta, 
    uint256 /*_lastIncreasedTime*/
  ) public pure returns (uint256) {
    return (_nextPrice*_sizeDelta+_averagePrice*_size)/(_size+_sizeDelta);
  }
  function getDelta(address _indexToken, uint256 _size, uint256 _averagePrice, bool _isLong, uint256 _lastIncreasedTime) public override view returns (bool, uint256) {
    if(_size == 0){
      return (false, 0);
    }
    uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
    uint256 priceDelta = _averagePrice > price ? _averagePrice-price: price-_averagePrice;
    uint256 delta = _size * priceDelta / _averagePrice;

    bool hasProfit;

    if (_isLong) {
        hasProfit = price > _averagePrice;
    } else {
        hasProfit = _averagePrice > price;
    }

    uint256 minBps = block.timestamp > _lastIncreasedTime+dipxStorage.minProfitTime() ? 0 : dipxStorage.minProfitBasisPoints(_indexToken);
    if (hasProfit && delta*BASIS_POINTS_DIVISOR <= _size*minBps) {
        delta = 0;
    }

    return (hasProfit, delta);
  }

  function _calculateFee(uint256 positionFee, int256 fundingFee) private pure returns(uint256 fee){
    if(fundingFee<0){
      uint256 absFundingFee = uint256(-fundingFee);
      if(absFundingFee > positionFee){
        fee = 0;
      }else{
        fee = positionFee - absFundingFee;
      }
    }else{
      fee = positionFee + uint256(fundingFee);
    }
  }

  function _decreaseBorrowed(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    bool _isLong
  ) private {
    Position memory position = getPosition(_account, _indexToken, _collateralToken, _isLong);

    uint256 borrowed = position.size>position.collateral ? position.size-position.collateral:0;
    globalBorrowAmounts[_collateralToken] = globalBorrowAmounts[_collateralToken] - borrowed;
  }
  function _increaseBorrowed(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    bool _isLong
  ) private {
    Position memory position = getPosition(_account, _indexToken, _collateralToken, _isLong);

    uint256 borrowed = position.size>position.collateral ? position.size-position.collateral:0;
    globalBorrowAmounts[_collateralToken] = globalBorrowAmounts[_collateralToken] + borrowed;
  }

  function updateCumulativeFundingRate(address _indexToken,address _collateralToken) public {
    dipxStorage.updateCumulativeFundingRate(_indexToken, _collateralToken);
  }

  function getMaxPrice(address _token) public view override returns (uint256) {
    return IVaultPriceFeed(dipxStorage.priceFeed()).getPrice(_token, true);
  }

  function getMinPrice(address _token) public view override returns (uint256) {
    return IVaultPriceFeed(dipxStorage.priceFeed()).getPrice(_token, false);
  }
  function validateLiquidation(address _account, address _collateralToken, address _indexToken, bool _isLong, bool _raise) external override returns (uint256, uint256){
    updateCumulativeFundingRate(_indexToken, _collateralToken);
    return _validateLiquidation(_account, _collateralToken, _indexToken, _isLong, _raise);
  }

  function _validateLiquidation(address _account, address _collateralToken, address _indexToken, bool _isLong, bool _raise) private view returns (uint256, uint256) {
    bytes32 key = getPositionKey(_account, _indexToken, _collateralToken, _isLong);
    Position memory position = positions[key];

    uint256 fee;
    {
    uint256 positionFees =  _calculatePositionFee(_account,_indexToken, _collateralToken, position.size);
    int256 fundingFees = _calculateFundingFee(_account, _indexToken, _collateralToken, _isLong);
    fee = _calculateFee(positionFees, fundingFees);
    }
    (bool hasProfit, uint256 delta) = getDelta(_indexToken, position.size, position.averagePrice, _isLong, position.lastIncreasedTime);
    if (!hasProfit && position.collateral < delta) {
        if (_raise) { revert("Position: losses exceed collateral"); }
        return (1, fee);
    }

    uint256 remainingCollateral = position.collateral;
    if (!hasProfit) {
        remainingCollateral = position.collateral - delta;
    }

    if (remainingCollateral < fee) {
        if (_raise) { revert("fees exceed collateral"); }
        return (1, remainingCollateral);
    }

    if(remainingCollateral*dipxStorage.maxLeverage() < position.size){
      if (_raise) { revert("maxLeverage exceeded"); }
      return (2, fee);
    }

    return (0, fee);
  }
  function _validateLeverage(address /*_collateralToken */, uint256 _size, uint256 _collateral) private view{
    if(_size <= _collateral){
      return;
    }
    require(_collateral*dipxStorage.maxLeverage() >= _size, "PositionManager: leverage exceed");
  }
  function _validatefee(address _collateralToken) private view{
    uint256 fee = dipxStorage.getTokenGasFee(_collateralToken);
    if(fee>0){
      require(msg.value >= fee, "PositionManager: GASFEE_INSUFFICIENT");
    }
  }
  function _validateRouter(address _account) private view {
    if (msg.sender == _account) { return; }
    if (msg.sender == dipxStorage.router()) { return; }
    require(dipxStorage.approvedRouters(_account,msg.sender), "PositionManager: invalid router");
  }
  function _validateIncrease(address _token) private view{
    require(!dipxStorage.increasePaused(), "PositionManager: increase paused");
    require(!dipxStorage.tokenIncreasePaused(_token), "PositionManager: increase paused");
  }
  function _validateDecrease(address _token) private view{
    require(!dipxStorage.decreasePaused(), "PositionManager: decrease paused");
    require(!dipxStorage.tokenDecreasePaused(_token), "PositionManager: decrease paused");
  }
  function _validateLiquidate(address _token) private view{
    require(!dipxStorage.liquidatePaused(), "PositionManager: trading paused");
    require(!dipxStorage.tokenLiquidatePaused(_token), "PositionManager: trading paused");
  }

  function transferOutETH(address _to, uint256 _amount) external onlyOwner{
    TransferHelper.safeTransferETH(_to, _amount);
  }
}
