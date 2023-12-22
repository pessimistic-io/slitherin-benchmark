// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./TimelockControllerUpgradeable.sol";
import "./ILpManager.sol";
import "./IPositionManager.sol";
import "./IDipxStorage.sol";
import "./IStorageSet.sol";
import "./IMixedLP.sol";
import "./ISingleLP.sol";

contract TimeLock is Initializable,OwnableUpgradeable,TimelockControllerUpgradeable{
  event SchedultSetMinter(address token, address minter, bool active);
  event ExecuteSetMinter(address token, address minter, bool active);

  function initialize(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors
  ) public initializer{
    __Ownable_init();
    __TimelockController_init(minDelay, proposers, executors);
  }

  function setDipxStorage(address _target, address _dipxStorage) external onlyOwner{
    IStorageSet(_target).setDipxStorage(_dipxStorage);
  }
  function setLpManager(address _dipxStorage, address _lpManager) external onlyOwner{
    IDipxStorage(_dipxStorage).setLpManager(_lpManager);
  }
  function setPositionManager(address _dipxStorage, address _positionManager) external onlyOwner{
    IDipxStorage(_dipxStorage).setPositionManager(_positionManager);
  }
  function setVault(address _dipxStorage, address _vault) external onlyOwner{
    IDipxStorage(_dipxStorage).setVault(_vault);
  }
  function setRouter(address _dipxStorage, address _router) external onlyOwner{
    IDipxStorage(_dipxStorage).setRouter(_router);
  }
  function setPriceFeed(address _dipxStorage, address _priceFeed) external onlyOwner{
    IDipxStorage(_dipxStorage).setPriceFeed(_priceFeed);
  }
  function setFundingRateFactor(address _storage,uint256 _fundingRateFactor) external onlyOwner {
    IDipxStorage(_storage).setFundingRateFactor(_fundingRateFactor);
  }
  function setFundingInterval(address _storage,uint256 _fundingInterval) external onlyOwner{
    IDipxStorage(_storage).setFundingInterval(_fundingInterval);
  }
  function setDefaultGasFee(address _storage,uint256 _gasFee) external onlyOwner{
    IDipxStorage(_storage).setDefaultGasFee(_gasFee);
  }
  function setTokenGasFee(
    address _storage,
    address _collateralToken, 
    bool _requireFee, 
    uint256 _fee
  ) external onlyOwner{
    IDipxStorage(_storage).setTokenGasFee(_collateralToken, _requireFee, _fee);
  }

  function setLpPoolAdtive(address _lpManager,address _pool, bool _isLp, bool _active) external onlyOwner{
    ILpManager(_lpManager).setPoolActive(_pool, _isLp, _active);
  }
  function setGreylistedTokens(address _storage,address[] memory _tokens, bool[] memory _disables) external onlyOwner{
    IDipxStorage(_storage).setGreyListTokens(_tokens,_disables);
  }

  function positionGreylistAddress(address _storage, address _address) external onlyOwner{
    IDipxStorage(_storage).greylistAddress(_address);
  }
  function positionToggleIncrease(address _storage) external onlyOwner {
    IDipxStorage(_storage).toggleIncrease();
  }
  function positionToggleTokenIncrease(address _storage,address _token) external onlyOwner {
    IDipxStorage(_storage).toggleTokenIncrease(_token);
  }
  function positionToggleDecrease(address _storage) external onlyOwner {
    IDipxStorage(_storage).toggleDecrease();
  }
  function positionToggleTokenDecrease(address _storage,address _token) external onlyOwner {
    IDipxStorage(_storage).toggleTokenDecrease(_token);
  }
  function positionToggleLiquidate(address _storage) external onlyOwner {
    IDipxStorage(_storage).toggleLiquidate();
  }
  function positionToggleTokenLiquidate(address _storage,address _token) external onlyOwner {
    IDipxStorage(_storage).toggleTokenLiquidate(_token);
  }
  function setMaxLeverage(address _storage,uint256 _maxLeverage) external onlyOwner{
    IDipxStorage(_storage).setMaxLeverage(_maxLeverage);
  }
  function setLiquidator(address _storage,address _liquidator, bool _isActive) external onlyOwner{
    IDipxStorage(_storage).setLiquidator(_liquidator, _isActive);
  }
  function setMinProfit(
    address _storage,
    uint256 _minProfitTime,
    address[] memory _indexTokens, 
    uint256[] memory _minProfitBps
  ) external onlyOwner{
    IDipxStorage(_storage).setMinProfit(_minProfitTime, _indexTokens, _minProfitBps);
  }
  
  function setAccountsFeePoint(
    address _dipxStorage,
    address[] memory _accounts, 
    bool[] memory _whitelisted, 
    uint256[] memory _feePoints
  ) external onlyOwner{
    IDipxStorage(_dipxStorage).setAccountsFeePoint(_accounts, _whitelisted, _feePoints);
  }
  function setFeeTo(
    address _dipxStorage,
    address _feeTo
  ) external onlyOwner{
    IDipxStorage(_dipxStorage).setFeeTo(_feeTo);
  }
  function setPositionFeePoints(
    address _dipxStorage,
    uint256 _point, 
    uint256 _lpPoint
  ) external onlyOwner{
    IDipxStorage(_dipxStorage).setPositionFeePoints(_point, _lpPoint);
  }
  function setTokenPositionFeePoints(
    address _dipxStorage,
    address[] memory _lpTokens, 
    uint256[] memory _rates
  ) external onlyOwner{
    IDipxStorage(_dipxStorage).setTokenPositionFeePoints(_lpTokens, _rates);
  }
  function setLpTaxPoints(
    address _dipxStorage,
    address _pool,
    uint256 _buyLpFeePoints, 
    uint256 _sellLpFeePoints
  ) external onlyOwner{
    IDipxStorage(_dipxStorage).setLpTaxPoints(_pool, _buyLpFeePoints, _sellLpFeePoints);
  }
}

