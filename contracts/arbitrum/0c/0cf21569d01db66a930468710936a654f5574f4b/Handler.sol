// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;
import "./IHandler.sol";
import "./IDipxStorage.sol";
import "./ILpManager.sol";
import "./IPositionManager.sol";
import "./ILP.sol";
import "./IMixedLP.sol";
import "./ISingleLP.sol";
import "./IReferral.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./EnumerableSet.sol";
import "./IERC20.sol";

contract Handler is IHandler,Initializable,OwnableUpgradeable{
  using EnumerableSet for EnumerableSet.Bytes32Set;

  uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;
  int256 constant OFFSET19700101 = 2440588;

  IDipxStorage public dipxStorage;
  mapping(address => bool) public plugins;
  // pool => (date => volume)
  mapping(address => mapping(uint256 => PoolVolume)) public dailyPoolVolumes;
  // account => keys
  mapping(address => EnumerableSet.Bytes32Set) private userVolumeKeys;
  mapping(bytes32 => PoolVolume) public userDailyVolumes;

  // pool => (date => liquidity)
  mapping(address => mapping(uint256 => PoolLiquidity)) public dailyPoolLiquidity;

  // date => keys
  mapping(uint256 => EnumerableSet.Bytes32Set) private dailyVolumeKeys;

  modifier onlyPlugin(){
    require(plugins[msg.sender], "Handler: caller is not the plugin");
    _;
  }

  function initialize(address _dipxStorage) public initializer {
    __Ownable_init();
    dipxStorage = IDipxStorage(_dipxStorage);
  }

  function getUserVolume(bytes32 key) public override view returns(PoolVolume memory){
    return userDailyVolumes[key];
  }
  function getPoolVolume(address _pool, uint256 _date) public override view returns(PoolVolume memory){
    return dailyPoolVolumes[_pool][_date];
  }

  function getUserVolumeKeyLength(address account) public view returns(uint256){
    return userVolumeKeys[account].length();
  }
  function getUserVolumeKeyAt(address account, uint256 index) public view returns(bytes32){
    return userVolumeKeys[account].at(index);
  }

  function getDailyVolumeKeyLength(uint256 date) public view returns(uint256){
    return dailyVolumeKeys[date].length();
  }
  function getDailyVolumeKeyAt(uint256 date, uint256 index) public view returns(bytes32){
    return dailyVolumeKeys[date].at(index);
  }
  
  function getUserVolumes(address account,uint256 begin,uint256 end) public view returns(PoolVolume[] memory){
    uint256 len = userVolumeKeys[account].length();
    uint256 size;
    for (uint256 i = 0; i < len; i++) {
      bytes32 key = userVolumeKeys[account].at(i);
      if(begin <= userDailyVolumes[key].date && userDailyVolumes[key].date < end){
        size ++;
      }
    }

    uint256 count;
    PoolVolume[] memory volumes = new PoolVolume[](size);
    for (uint256 i = 0; i < len; i++) {
      bytes32 key = userVolumeKeys[account].at(i);
      if(begin <= userDailyVolumes[key].date && userDailyVolumes[key].date < end){
        volumes[count] = userDailyVolumes[key];
        count ++;
      }
    }

    return volumes;
  }

  function getDailyVolumes(address pool, uint256 date) public view returns(PoolVolume[] memory){
    uint256 len = dailyVolumeKeys[date].length();
    uint256 size;
    for (uint256 i = 0; i < len; i++) {
      bytes32 key = dailyVolumeKeys[date].at(i);
      if(userDailyVolumes[key].pool == pool){
        size ++;
      }
    }

    uint256 count;
    PoolVolume[] memory volumes = new PoolVolume[](size);
    for (uint256 i = 0; i < len; i++) {
      bytes32 key = dailyVolumeKeys[date].at(i);
      if(userDailyVolumes[key].pool == pool){
        volumes[count] = userDailyVolumes[key];
        count ++;
      }
    }

    return volumes;
  }

  function setDipxStorage(address _dipxStorage) external onlyOwner{
    dipxStorage = IDipxStorage(_dipxStorage);
  }

  function setPlugins(address[] memory _plugins, bool _enable) external onlyOwner{
    for (uint256 i = 0; i < _plugins.length; i++) {
      plugins[_plugins[i]] = _enable;
    }
  }

  function timestampToDate(uint256 timestamp) internal pure returns (uint256 year, uint256 month, uint256 day) {
    unchecked {
      (year, month, day) = _daysToDate(timestamp / SECONDS_PER_DAY);
    }
  }
  function timestampToDateNumber(uint256 timestamp) internal pure returns(uint256 date){
    (uint256 year,uint256 month,uint256 day) = timestampToDate(timestamp);
    return year*10000 + month*100 + day;
  }
  function _daysToDate(uint256 _days) internal pure returns (uint256 year, uint256 month, uint256 day) {
    unchecked {
      int256 __days = int256(_days);

      int256 L = __days + 68569 + OFFSET19700101;
      int256 N = (4 * L) / 146097;
      L = L - (146097 * N + 3) / 4;
      int256 _year = (4000 * (L + 1)) / 1461001;
      L = L - (1461 * _year) / 4 + 31;
      int256 _month = (80 * L) / 2447;
      int256 _day = L - (2447 * _month) / 80;
      L = _month / 11;
      _month = _month + 2 - 12 * L;
      _year = 100 * (N - 49) + _year + L;

      year = uint256(_year);
      month = uint256(_month);
      day = uint256(_day);
    }
  }

  function _increaseVolume(
    address account,
    address indexToken, 
    address collateralToken,
    bool isLong,
    uint256 sizeDelta,
    uint256 fee
  ) private {
    IPositionManager.Position memory position = IPositionManager(dipxStorage.positionManager()).getPosition(account,indexToken,collateralToken,isLong);
    uint256 date = timestampToDateNumber(block.timestamp);
    uint256 poolPrice = ILpManager(dipxStorage.lpManager()).getPoolPrice(collateralToken, true, true, true);

    PoolVolume storage volume = dailyPoolVolumes[collateralToken][date];
    volume.pool = collateralToken;
    volume.date = date;
    volume.value = volume.value + sizeDelta;
    volume.fee = volume.fee + fee;
    volume.valueInUsd = volume.valueInUsd + sizeDelta*poolPrice;
    volume.feeInUsd = volume.feeInUsd + fee*poolPrice;

    PoolVolume storage totalVolume = dailyPoolVolumes[collateralToken][0];
    totalVolume.pool = collateralToken;
    totalVolume.date = 0;
    totalVolume.value = totalVolume.value + sizeDelta;
    totalVolume.valueInUsd = totalVolume.valueInUsd + sizeDelta*poolPrice;
    totalVolume.fee = totalVolume.fee + fee;
    totalVolume.feeInUsd = totalVolume.feeInUsd + fee*poolPrice;

    bytes32 key = keccak256(abi.encodePacked(account,date,collateralToken));
    userVolumeKeys[account].add(key);
    PoolVolume storage userVolume = userDailyVolumes[key];
    userVolume.pool = collateralToken;
    userVolume.date = date;
    userVolume.value = userVolume.value + sizeDelta;
    userVolume.valueInUsd = userVolume.valueInUsd + sizeDelta*poolPrice;
    userVolume.fee = userVolume.fee + fee;
    userVolume.feeInUsd = userVolume.feeInUsd + fee*poolPrice;
    if(block.timestamp - position.lastIncreasedTime >= dipxStorage.minProfitTime()){
      userVolume.realValue = userVolume.realValue + sizeDelta;
      userVolume.realValueInUsd = userVolume.realValueInUsd + sizeDelta*poolPrice;
    }

    dailyVolumeKeys[date].add(key);

    bytes32 userGlobalKey = keccak256(abi.encodePacked(account,uint256(0),collateralToken));
    PoolVolume storage userTotalVolume = userDailyVolumes[userGlobalKey];
    userTotalVolume.pool = collateralToken;
    userTotalVolume.date = 0;
    userTotalVolume.value = userTotalVolume.value + sizeDelta;
    userTotalVolume.valueInUsd = userTotalVolume.valueInUsd + sizeDelta*poolPrice;
    userTotalVolume.fee = userTotalVolume.fee + fee;
    userTotalVolume.feeInUsd = userTotalVolume.feeInUsd + fee*poolPrice;
    if(block.timestamp - position.lastIncreasedTime >= dipxStorage.minProfitTime()){
      userTotalVolume.realValue = userTotalVolume.realValue + sizeDelta;
      userTotalVolume.realValueInUsd = userTotalVolume.realValueInUsd + sizeDelta*poolPrice;
    }
  }

  function _updatePoolLiquidity(address pool) private{
    uint256 date = timestampToDateNumber(block.timestamp);
    PoolLiquidity storage pl = dailyPoolLiquidity[pool][date];
    pl.pool = pool;
    pl.date = date;
    pl.totalSupply = IERC20(pool).totalSupply();
    if(ILP(pool).isMixed()){
      pl.aum = IMixedLP(pool).getAum(true);
      pl.price = IMixedLP(pool).getPrice(true, true, true);
      pl.supplyWithPnl = IMixedLP(pool).getSupplyWithPnl(true,true);
    }else{
      pl.aum = ISingleLP(pool).tokenReserve();
      pl.price = ISingleLP(pool).getPrice(address(dipxStorage), true, true);
      pl.supplyWithPnl = ISingleLP(pool).getSupplyWithPnl(address(dipxStorage),true,true);
    }
  }

  function beforeAddLiquidity(address collateralToken,address targetPool,address to) external override onlyPlugin{

  }

  function afterAddLiquidity(address /*collateralToken*/,address targetPool,address /*to*/) external override onlyPlugin{
    _updatePoolLiquidity(targetPool);
  }

  function beforeRemoveLiquidity(address pool,address receiveToken, address to) external override onlyPlugin{

  }

  function afterRemoveLiquidity(address pool,address /*receiveToken*/, address /*to*/) external override onlyPlugin{
    _updatePoolLiquidity(pool);
  }

  function beforeIncreasePosition(
    address account,
    address indexToken, 
    address collateralToken,
    uint256 sizeDelta,
    uint256 collateralDelta,
    bool isLong
  ) external override onlyPlugin{

  }

  function afterIncreasePosition(
    address account,
    address indexToken, 
    address collateralToken,
    uint256 sizeDelta,
    uint256 /*collateralDelta*/,
    bool isLong,
    uint256 /*price*/,
    uint256 fee
  ) external override onlyPlugin{
    _increaseVolume(account, indexToken, collateralToken,isLong, sizeDelta, fee);
    _updatePoolLiquidity(collateralToken);
  }

  function beforeDecreasePosition(
    address account,
    address indexToken, 
    address collateralToken, 
    uint256 sizeDelta, 
    uint256 collateralDelta, 
    bool isLong, 
    address receiver
  ) external override onlyPlugin{

  }

  function afterDecreasePosition(
    address account,
    address indexToken, 
    address collateralToken, 
    uint256 sizeDelta, 
    uint256 /*collateralDelta*/,
    bool isLong, 
    address /*receiver*/,
    uint256 fee
  ) external override onlyPlugin{
    _increaseVolume(account, indexToken, collateralToken,isLong, sizeDelta, fee);
    _updatePoolLiquidity(collateralToken);
  }

  function beforeLiquidatePosition(
    address account, 
    address indexToken, 
    address collateralToken, 
    bool isLong,
    address feeReceiver
  ) external override onlyPlugin{

  }

  function afterLiquidatePosition(
    address account, 
    address indexToken, 
    address collateralToken, 
    bool isLong,
    address /*feeReceiver*/,
    uint256 size, 
    uint256 /*collateral*/, 
    uint256 /*markPrice*/, 
    uint256 /*liqFee*/,
    uint256 marginFee
  ) external override onlyPlugin{
    _increaseVolume(account, indexToken, collateralToken,isLong, size, marginFee);
    _updatePoolLiquidity(collateralToken);
  }
}

