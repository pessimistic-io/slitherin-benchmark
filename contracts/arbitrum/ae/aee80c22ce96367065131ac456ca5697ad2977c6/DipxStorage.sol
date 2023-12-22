// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IVault.sol";
import "./IDipxStorage.sol";
import "./IDipxStorageOld.sol";
import "./ILpManager.sol";
import "./IPositionManager.sol";
import "./IVaultPriceFeed.sol";
import "./Math.sol";
import "./IERC721.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract DipxStorage is Initializable,OwnableUpgradeable,IDipxStorage{
  bool public isInitialized;
  address public override vault;
  address public override lpManager;
  address public override positionManager;
  address public override router;
  address public override priceFeed;
  address public override feeTo;

  uint256 public constant override BASIS_POINT_DIVISOR = 100000000;
  uint256 public constant MAX_POSITION_FEE_POINTS = 500000; //500000=0.5% 

  uint256 public positionFeePoints;  //100000=0.1% 
  uint256 public lpFeePoints;       //70000000/100000000=70% position fee to LP
  mapping(address => uint256) public tokenPositionFeePoints;  //token position fee point
  mapping(address => uint256) public accountPositionFeePoints;  //account custom fee point
  mapping(address => bool) public positionFeeWhitelist;  //position fee whitelist
  uint256 public defaultGasFee;
  mapping(address => uint256) public tokenGasFees;
  mapping(address => bool) public noRequireGasFees;

  // pool address => point, 100=0.1%
  mapping(address => uint256) buyLpTaxPoints;
  mapping(address => uint256) sellLpTaxPoints;

  uint256 public fundingInterval;
  uint256 public fundingRateFactor;
  uint256 public constant MAX_FUNDING_RATE_FACTOR = 1000000; // 1%
  // cumulativeFundingRates tracks the funding rates based on utilization
  // (index => (collateral => fundingRate))
  mapping(address => mapping(address => FeeRate)) public cumulativeFundingRates_;
  // lastFundingTimes tracks the last time funding was updated for a token
  // (index => (collateral => lastFundingTime))
  mapping(address => mapping(address => uint256)) public override lastFundingTimes;
  SkewRule[] public defaultSkewRules;
  mapping(address => SkewRule[]) public tokenSkewRules;

  address public override eth;
  address public btc;
  uint8 public override nativeCurrencyDecimals;
  address public override nativeCurrency;
  string public override nativeCurrencySymbol;

  address public override handler;
  address public override referral;
  address public override genesisPass;

  uint256 public gpDiscount;    //10000000 for 10% discount

  mapping(address => bool) public override greylistedTokens;
  mapping(address => bool) public override greylist;
  bool public override increasePaused; // For emergencies
  mapping(address => bool) public override tokenIncreasePaused; // for emergencies
  bool public override decreasePaused; // For emergencies
  mapping(address => bool) public override tokenDecreasePaused; // for emergencies
  bool public override liquidatePaused; // For emergencies
  mapping(address => bool) public override tokenLiquidatePaused; // for emergencies

  uint256 public override maxLeverage;
  uint256 public override minProfitTime;
  mapping (address => uint256) public override minProfitBasisPoints;
  mapping (address => mapping (address => bool)) public override approvedRouters;
  mapping (address => bool) public override isLiquidator;

  event InitConfig(
    address _genesisPass,
    address _feeTo,
    address _vault, 
    address _lpManager, 
    address _positionManager,
    address _priceFeed,
    address _router,
    address _referral,
    uint256 _positionFeePoints,
    uint256 _lpFeePoints,
    uint256 _fundingRateFactor,
    uint256 _gasFee
  );
  event SetContracts(
    address _genesisPass,
    address _feeTo,
    address _vault, 
    address _lpManager, 
    address _positionManager,
    address _priceFeed,
    address _router,
    address _handler,
    address _referral
  );
  event SetGenesisPass(address _genesisPass, uint256 _gpDiscount);
  event SetDefaultGasFee(uint256 _gasFee);
  event SetTokenGasFee(address _collateralToken, bool _requireFee, uint256 _fee);
  event SetReferral(address _referral);
  event SetHandler(address _handler);
  event SetLpManager(address _lpManager);
  event SetPositionManager(address _positionManager);
  event SetVault(address _vault);
  event SetPriceFeed(address _priceFeed);
  event SetRouter(address _router);
  event SetFundingInterval(uint256 _fundingInterval);
  event SetFundingRateFactor(uint256 _fundingRateFactor);
  event SetAccountsFeePoint(address[] _accounts, bool[] _whitelisted, uint256[] _feePoints);
  event SetFeeTo(address _feeTo);
  event SetPositionFeePoints(uint256 _point, uint256 _lpPoint);
  event SetTokenPositionFeePoints(address[] _lpTokens, uint256[] _rates);
  event SetLpTaxPoints(address _pool, uint256 _buyFeePoints, uint256 _sellFeePoints);

  function migration(
    address _oldStorage,
    address[] memory indexTokens, 
    address[] memory collateralTokens
  ) external onlyOwner{
    IDipxStorageOld oldStorage = IDipxStorageOld(_oldStorage);
    for (uint256 i = 0; i < indexTokens.length; i++) {
      for (uint256 j = 0; j < collateralTokens.length; j++) {
        address indexToken = indexTokens[i];
        address collateralToken = collateralTokens[j];

        uint256 rate = oldStorage.cumulativeFundingRates(indexToken,collateralToken);
        cumulativeFundingRates_[indexToken][collateralToken] = FeeRate(rate,rate);

        lastFundingTimes[indexToken][collateralToken] = oldStorage.lastFundingTimes(indexToken, collateralToken);
      }
    }
  }
  function initialize(
    uint8 _nativeCurrencyDecimals,
    address _eth,
    address _btc,
    address _nativeCurrency,
    string memory _nativeCurrencySymbol
  ) public initializer {
    __Ownable_init();
    nativeCurrencyDecimals = _nativeCurrencyDecimals;
    eth = _eth;
    btc = _btc;
    nativeCurrency = _nativeCurrency;
    nativeCurrencySymbol = _nativeCurrencySymbol;
    maxLeverage = 100;
  }

  function initConfig(
    address _genesisPass,
    address _feeTo,
    address _vault, 
    address _lpManager, 
    address _positionManager,
    address _priceFeed,
    address _router,
    address _referral,
    uint256 _positionFeePoints,
    uint256 _lpFeePoints,
    uint256 _fundingRateFactor,
    uint256 _gasFee
  ) external override onlyOwner{
    require(!isInitialized, "Storage: already initialized");
    isInitialized = true;

    genesisPass = _genesisPass;
    feeTo = _feeTo;
    vault = _vault;
    lpManager = _lpManager;
    positionManager = _positionManager;
    priceFeed = _priceFeed;
    router = _router;
    referral = _referral;
    require(_lpFeePoints<=BASIS_POINT_DIVISOR && _positionFeePoints<=MAX_POSITION_FEE_POINTS, "error fee point");
    positionFeePoints = _positionFeePoints;
    lpFeePoints = _lpFeePoints;

    gpDiscount = BASIS_POINT_DIVISOR / 5;  // 20% discount
    fundingInterval = 1 hours;
    fundingRateFactor = _fundingRateFactor;

    defaultGasFee = _gasFee;

    emit InitConfig(
      _genesisPass,
      _feeTo, 
      _vault, 
      _lpManager, 
      _positionManager, 
      _priceFeed, 
      _router, 
      _referral, 
      _positionFeePoints, 
      _lpFeePoints, 
      _fundingRateFactor, 
      _gasFee
    );
  }

  function setContracts(
    address _genesisPass,
    address _feeTo,
    address _vault, 
    address _lpManager, 
    address _positionManager,
    address _priceFeed,
    address _router,
    address _handler,
    address _referral
  ) external override onlyOwner{
    genesisPass = _genesisPass;
    feeTo = _feeTo;
    vault = _vault;
    lpManager = _lpManager;
    positionManager = _positionManager;
    priceFeed = _priceFeed;
    router = _router;
    handler = _handler;
    referral = _referral;

    emit SetContracts(
      _genesisPass,
      _feeTo,
      _vault, 
      _lpManager, 
      _positionManager,
      _priceFeed,
      _router,
      _handler,
      _referral
    );
  }
  function setGenesisPass(address _genesisPass, uint256 _gpDiscount) external override onlyOwner{
    require(_gpDiscount <= BASIS_POINT_DIVISOR, "error gp point");
    genesisPass = _genesisPass;
    gpDiscount = _gpDiscount;
    emit SetGenesisPass(_genesisPass, _gpDiscount);
  }
  function setDefaultGasFee(uint256 _gasFee) external override onlyOwner{
    defaultGasFee = _gasFee;
    emit SetDefaultGasFee(_gasFee);
  }
  function setTokenGasFee(address _collateralToken, bool _requireFee, uint256 _fee) external override onlyOwner{
    noRequireGasFees[_collateralToken] = !_requireFee;
    tokenGasFees[_collateralToken] = _requireFee?_fee:0;

    emit SetTokenGasFee(_collateralToken, _requireFee, _fee);
  }
  function getTokenGasFee(address _collateralToken) public override view returns(uint256){
    if(noRequireGasFees[_collateralToken]){
      return 0;
    }
    if(tokenGasFees[_collateralToken]>0){
      return tokenGasFees[_collateralToken];
    }
    return defaultGasFee;
  }

  function setReferral(address _referral) external override onlyOwner{
    referral = _referral;
    emit SetReferral(_referral);
  }
  function setHandler(address _handler) external override onlyOwner{
    handler = _handler;
    emit SetHandler(_handler);
  }
  function setLpManager(address _lpManager) external override onlyOwner{
    lpManager = _lpManager;
    emit SetLpManager(_lpManager);
  }
  function setPositionManager(address _positionManager) external override onlyOwner{
    positionManager = _positionManager;
    emit SetPositionManager(_positionManager);
  }
  function setVault(address _vault) external override onlyOwner{
    vault = _vault;
    emit SetVault(_vault);
  }
  function setPriceFeed(address _priceFeed) external override onlyOwner{
    priceFeed = _priceFeed;
    emit SetPriceFeed(_priceFeed);
  }
  function setRouter(address _router) external override onlyOwner{
    router = _router;
    emit SetRouter(_router);
  }

  function setFundingInterval(uint256 _fundingInterval) external override onlyOwner{
    require(_fundingInterval>0, "fundingInterval error");
    fundingInterval = _fundingInterval;
    emit SetFundingInterval(_fundingInterval);
  }
  function setFundingRateFactor(uint256 _fundingRateFactor) external override onlyOwner {
    fundingRateFactor = _fundingRateFactor;
    emit SetFundingRateFactor(_fundingRateFactor);
  }

  function setAccountsFeePoint(address[] memory _accounts, bool[] memory _whitelisted, uint256[] memory _feePoints) external override onlyOwner{
    require(_accounts.length==_whitelisted.length && _accounts.length==_feePoints.length, "invalid params");
    for (uint256 i = 0; i < _accounts.length; i++) {
      positionFeeWhitelist[_accounts[i]] = _whitelisted[i];
      require(_feePoints[i]<=MAX_POSITION_FEE_POINTS, "exceed max point");
      accountPositionFeePoints[_accounts[i]] = _whitelisted[i]?_feePoints[i]:0;
    }
    emit SetAccountsFeePoint(_accounts, _whitelisted, _feePoints);
  }

  function setFeeTo(address _feeTo) external override onlyOwner{
    feeTo = _feeTo;
    emit SetFeeTo(_feeTo);
  }

  function setPositionFeePoints(uint256 _point, uint256 _lpPoint) external override onlyOwner{
    require(_lpPoint<=BASIS_POINT_DIVISOR && _point<=MAX_POSITION_FEE_POINTS, "exceed max point");
    positionFeePoints = _point;
    lpFeePoints = _lpPoint;
    emit SetPositionFeePoints(_point, _lpPoint);
  }

  function setTokenPositionFeePoints(address[] memory _lpTokens, uint256[] memory _rates) external override onlyOwner{
    require(_lpTokens.length == _rates.length);
    for (uint256 i = 0; i < _lpTokens.length; i++) {
      tokenPositionFeePoints[_lpTokens[i]] = _rates[i];
    }
    emit SetTokenPositionFeePoints(_lpTokens, _rates);
  }

  function setDefaultSkewRules(
    SkewRule[] memory _rules
  ) external override onlyOwner{
    delete defaultSkewRules;
    for (uint256 i = 0; i < _rules.length; i++) {
      defaultSkewRules.push(_rules[i]);
    }
  }
  function setTokenSkewRules(
    address _collateralToken,
    SkewRule[] memory _rules
  ) external override onlyOwner{
    require(_collateralToken != address(0));
    delete tokenSkewRules[_collateralToken];
    SkewRule[] storage rules = tokenSkewRules[_collateralToken];
    for (uint256 i = 0; i < _rules.length; i++) {
      rules.push(_rules[i]);
    }
  }

  function getSkewRules(address _collateralToken) public view returns(SkewRule[] memory){
    SkewRule[] memory tokenRules = tokenSkewRules[_collateralToken];
    if(tokenRules.length>0){
      return tokenRules;
    }

    return defaultSkewRules;
  }

  function cumulativeFundingRates(address indexToken, address collateralToken) public override view returns(FeeRate memory){
    return cumulativeFundingRates_[indexToken][collateralToken];
  }

  function currentFundingFactor(address /*_account*/,address _indexToken, address _collateralToken, bool _isLong) public override view returns(int256) {
    IPositionManager.Position memory longPosition = IPositionManager(positionManager).getPosition(address(0), _indexToken, _collateralToken, true);
    IPositionManager.Position memory shortPosition = IPositionManager(positionManager).getPosition(address(0), _indexToken, _collateralToken, false);

    uint256 longSize = longPosition.size;
    uint256 shortSize = shortPosition.size;
    uint256 skew = _calculateSkew(longSize, shortSize);
    bool isLongSkew = longSize>shortSize;
    SkewRule[] memory rules = getSkewRules(_collateralToken);
    uint256 delta = longSize>shortSize?longSize-shortSize:shortSize-longSize;
    for (uint256 i = 0; i < rules.length; i++) {
      SkewRule memory rule = rules[i];
      if(rule.min <= skew && skew < rule.max && delta >= rule.delta){
        if(isLongSkew == _isLong){
          return int256(rule.heavy);
        }else{
          return rule.light;
        }
      }
    }
    
    return int256(BASIS_POINT_DIVISOR);
  }

  function _calculateSkew(uint256 leftSize, uint256 rightSize) private pure returns(uint256){
    uint256 totalSize = leftSize + rightSize;
    if(totalSize == 0){
      return BASIS_POINT_DIVISOR / 2;
    }
    if(leftSize == 0 || rightSize == 0){
      return BASIS_POINT_DIVISOR;
    }

    return Math.max(leftSize, rightSize) * BASIS_POINT_DIVISOR / totalSize;
  }

  function getFundingFee(
    address _account,
    address _indexToken, 
    address _collateralToken, 
    bool _isLong
  ) public override view returns (int256) {
    IPositionManager.Position memory position = IPositionManager(positionManager).getPosition(_account, _indexToken, _collateralToken, _isLong);

    if (position.size == 0 || position.size <= position.collateral) { return 0; }

    FeeRate memory rate = cumulativeFundingRates_[_indexToken][_collateralToken];
    uint256 feeRate = _isLong?rate.longRate:rate.shortRate;
    int256 fundingRate = int256(feeRate) - int256(position.entryFundingRate);
    if (fundingRate <= 0) { return 0; }   // funding fee < 0 not supported yet

    return int256(position.size-position.collateral) * fundingRate / int256(BASIS_POINT_DIVISOR);
  }

  function updateCumulativeFundingRate(address _indexToken,address _collateralToken) public override {
    if (lastFundingTimes[_indexToken][_collateralToken] == 0) {
      lastFundingTimes[_indexToken][_collateralToken] = block.timestamp;
      return;
    }

    if (lastFundingTimes[_indexToken][_collateralToken] >= block.timestamp) {
      return;
    }

    FeeRate storage rate = cumulativeFundingRates_[_indexToken][_collateralToken];
    rate.longRate = rate.longRate + getNextFundingRate(_indexToken, _collateralToken, true);
    rate.shortRate = rate.shortRate + getNextFundingRate(_indexToken, _collateralToken, false);

    lastFundingTimes[_indexToken][_collateralToken] = block.timestamp; // / fundingInterval * fundingInterval;
  }
  function getNextFundingRate(address _indexToken, address _collateralToken, bool _isLong) public view returns (uint256) {
    if (lastFundingTimes[_indexToken][_collateralToken] > block.timestamp) { 
      return 0; 
    }

    uint256 intervals = block.timestamp - lastFundingTimes[_indexToken][_collateralToken];
    int256 factor = currentFundingFactor(address(0), _indexToken, _collateralToken, _isLong);
    if(factor <= 0){
      return 0; // factor < 0 not supported yet
    }
    return fundingRateFactor* intervals * uint256(factor) / fundingInterval * BASIS_POINT_DIVISOR;
  }

  function getPositionFeePoints(address _collateralToken) public view override returns(uint256){
    uint256 rate = tokenPositionFeePoints[_collateralToken];
    if(rate>0){
      return rate;
    }
    return positionFeePoints;
  }

  function getLpPositionFee(address /*_collateralToken*/,uint256 totalFee) public view override returns(uint256){
    uint256 fee = totalFee * lpFeePoints / BASIS_POINT_DIVISOR;
    return fee;
  }

  function getPositionFee(address _account,address /*_indexToken*/, address _collateralToken, uint256 _tradeAmount) public view override returns(uint256){
    uint256 feePoint;
    if(positionFeeWhitelist[_account]){
      feePoint = accountPositionFeePoints[_account];
    }else{
      feePoint = getPositionFeePoints(_collateralToken);
      if(genesisPass != address(0)){
        if(IERC721(genesisPass).balanceOf(_account) > 0){
          feePoint = feePoint * (BASIS_POINT_DIVISOR-gpDiscount)/BASIS_POINT_DIVISOR;
        }
      }
    }
    uint256 fee = _tradeAmount * feePoint / BASIS_POINT_DIVISOR;
    return fee;
  }

  function setLpTaxPoints(address _pool, uint256 _buyFeePoints, uint256 _sellFeePoints) external override onlyOwner{
    buyLpTaxPoints[_pool] = _buyFeePoints;
    sellLpTaxPoints[_pool] = _sellFeePoints;
    emit SetLpTaxPoints(_pool, _buyFeePoints, _sellFeePoints);
  }

  function isEth(address _token) public view returns(bool){
    return _token == eth;
  }

  function isNativeCurrency(address _token) public override view returns(bool) {
    return _token == nativeCurrency;
  }

  function getTokenBalance(address _token, address _account) public view returns(uint256){
    if(isNativeCurrency(_token)){
      return _account.balance;
    }

    return IERC20(_token).balanceOf(_account);
  }

  function getTokenDecimals(address _token) public override view returns(uint256) {
    if(isNativeCurrency(_token)){
      return nativeCurrencyDecimals;
    }else{
      return IERC20Metadata(_token).decimals();
    }
  }

  function getTokenVaule(address _token, address _account, bool _maximise) public view returns(uint256){
    uint256 price = IVaultPriceFeed(priceFeed).getPrice(_token, _maximise);

    uint256 balance = getTokenBalance(_token, _account);
    return price * balance;
  }

  function getBuyLpFeePoints(address _pool, address /*_token*/,uint256 /*_delta*/) public view override returns(uint256) {
    return buyLpTaxPoints[_pool];
  }

  function getSellLpFeePoints(address _pool, address /*_outToken*/,uint256 /*_delta*/) public view override returns(uint256){
    return sellLpTaxPoints[_pool];
  }

  function setGreyListTokens(address[] memory _tokens, bool[] memory _disables) external override onlyOwner{
    require(_tokens.length == _disables.length);
    for (uint256 i = 0; i < _tokens.length; i++) {
      greylistedTokens[_tokens[i]] = _disables[i];
    }
  }

  function greylistAddress(address _address) external override onlyOwner {
    greylist[_address] = !(greylist[_address]);
  }
  function toggleIncrease() external override onlyOwner {
    increasePaused = !increasePaused;
  }
  function toggleTokenIncrease(address _token) external override onlyOwner {
    tokenIncreasePaused[_token] = !(tokenIncreasePaused[_token]);
  }
  function toggleDecrease() external override onlyOwner {
    decreasePaused = !decreasePaused;
  }
  function toggleTokenDecrease(address _token) external override onlyOwner {
    tokenDecreasePaused[_token] = !(tokenDecreasePaused[_token]);
  }
  function toggleLiquidate() external override onlyOwner {
    liquidatePaused = !liquidatePaused;
  }
  function toggleTokenLiquidate(address _token) external override onlyOwner {
    tokenLiquidatePaused[_token] = !(tokenLiquidatePaused[_token]);
  }

  function setMaxLeverage(uint256 _maxLeverage) external override onlyOwner{
    maxLeverage = _maxLeverage;
  }
  function setLiquidator(address _liquidator, bool _isActive) external override onlyOwner{
    isLiquidator[_liquidator] = _isActive;
  }

  function setMinProfit(uint256 _minProfitTime,address[] memory _indexTokens, uint256[] memory _minProfitBps) external override onlyOwner{
    require(_indexTokens.length == _minProfitBps.length);
    minProfitTime = _minProfitTime;
    for (uint256 i = 0; i < _indexTokens.length; i++) {
      minProfitBasisPoints[_indexTokens[i]] = _minProfitBps[i];
    }
  }

  function approveRouter(address _router, bool _enable) external override{
    approvedRouters[msg.sender][_router] = _enable;
  }

}
