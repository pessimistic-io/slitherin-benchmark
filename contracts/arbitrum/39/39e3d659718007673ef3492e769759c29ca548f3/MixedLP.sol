// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./Ownable.sol";
import "./IMixedLP.sol";
import "./TransferHelper.sol";
import "./IDipxStorage.sol";
import "./IPositionManager.sol";
import "./IVaultPriceFeed.sol";

contract MixedLP is Ownable, ERC20, IMixedLP{
  IDipxStorage public dipxStorage;

  mapping (address => uint256) public override tokenReserves;
  mapping (address => bool) public override isMinter;
  mapping (address => bool) public override isWhitelistedToken;
  address[] public override allTokens;

  modifier onlyMinter(){
    require(isMinter[msg.sender], "FORBIDDEN: onlyMinter");
    _;
  }

  constructor(string memory _name, string memory _symbol) ERC20(_name,_symbol){
  }

  receive() external payable{}

  function initialize(address _dipxStorage) public onlyOwner{
    dipxStorage = IDipxStorage(_dipxStorage);
  }
  function setDipxStorage(address _dipxStorage) external override onlyOwner{
    dipxStorage = IDipxStorage(_dipxStorage);
  }

  function isMixed() public override pure returns(bool){
    return true;
  }

  function allTokensLength() public override view returns(uint256) {
    return allTokens.length;
  }

  function setTokenConfigs(address[] memory _tokens, bool[] memory _isWhitelisteds) external override onlyOwner{
    require(_tokens.length == _isWhitelisteds.length);
    
    for (uint256 i = 0; i < _tokens.length; i++) {
      address token = _tokens[i];
      bool isWhitelisted = _isWhitelisteds[i];
      bool isTokenIn = isTokenPooled(token);
      if(!isTokenIn && _isWhitelisteds[i]){
        allTokens.push(token);
      }
      isWhitelistedToken[token] = isWhitelisted;
    }
  }

  function setMinter(address _minter, bool _active) external override onlyOwner{
    isMinter[_minter] = _active;
  }

  function mint(address _to, uint256 _amount) external override onlyMinter{
    _mint(_to, _amount);
  }
  function transferIn(address _token, uint256 _amount) external override onlyMinter{
    tokenReserves[_token] = tokenReserves[_token] + _amount;
  }
  function updateTokenReserves(address _token) external override onlyOwner {
    if(dipxStorage.isNativeCurrency(_token)){
      tokenReserves[_token] = address(this).balance;
    }else{
      tokenReserves[_token] = IERC20(_token).balanceOf(address(this));
    }
  }

  function withdrawEth(address _to, uint256 _amount) external override onlyMinter{
    address eth = dipxStorage.eth();
    require(tokenReserves[eth]>=_amount, "Insufficient eth");
    tokenReserves[eth] = tokenReserves[eth] - _amount;
    TransferHelper.safeTransferETH(_to, _amount);
  }
  function withdrawToken(address _token, address _to, uint256 _amount) external override onlyMinter{
    require(tokenReserves[_token]>=_amount, "Insufficient token");
    tokenReserves[_token] = tokenReserves[_token] - _amount;
    TransferHelper.safeTransfer(_token, _to, _amount);
  }

  function burn(uint256 amount) public override {
    _burn(msg.sender, amount);
  }

  function burnFrom(address account, uint256 amount) public override {
    _spendAllowance(account, msg.sender, amount);
    _burn(account, amount);
  }

  function isTokenPooled(address _token) public override view returns(bool){
    for (uint256 i = 0; i < allTokens.length; i++) {
      if(allTokens[i] == _token){
        return true;
      }
    }

    return false;
  }

  function getPrice(bool _maximise,bool _includeProfit, bool _includeLoss) public override view returns(uint256){
    uint256 priceDecimal = IVaultPriceFeed(dipxStorage.priceFeed()).decimals();
    uint256 supplyWithPnl = getSupplyWithPnl(_includeProfit,_includeLoss);
    if(supplyWithPnl == 0){
      return 10 ** priceDecimal; 
    }
    uint256 aum = getAum(_maximise);
    return aum/supplyWithPnl;
  }

  function getSupplyWithPnl(bool _includeProfit, bool _includeLoss) public view override returns(uint256){
    uint256 supply = totalSupply();
    IPositionManager positionManager = IPositionManager(dipxStorage.positionManager());
    uint256 len = positionManager.indexTokenLength();
    uint256 totalProfit;
    uint256 totalLoss;
    for (uint256 i = 0; i < len; i++) {
      address indexToken = positionManager.indexTokenAt(i);
      (bool hasProfit,uint256 pnl) = positionManager.calculateUnrealisedPnl(indexToken, address(this));
      if(hasProfit && _includeProfit){
        totalProfit = totalProfit + pnl;
      }
      if(!hasProfit && _includeLoss){
        totalLoss = totalLoss + pnl;
      }
    }
    
    supply = supply + totalProfit;
    if(supply >= totalLoss){
      supply = supply - totalLoss;
    }else{
      supply = 0;
    }
    
    return supply;
  }

  function adjustForDecimals(uint256 _value, uint256 _decimalsDiv, uint256 _decimalsMul) public pure returns (uint256) {
    return _value * (10 ** _decimalsMul) / (10 ** _decimalsDiv);
  }
  
  function getAum(bool maximise) public view override returns (uint256) {
    uint256 aum;
    for (uint256 i = 0; i < allTokens.length; i++) {
      address token = allTokens[i];

      uint256 price = IVaultPriceFeed(dipxStorage.priceFeed()).getPrice(token, maximise);
      uint8 tokenDecimals;
      if(dipxStorage.isNativeCurrency(token)){
        tokenDecimals = dipxStorage.nativeCurrencyDecimals();
      }else{
        tokenDecimals = IERC20Metadata(token).decimals();
      }

      aum = aum + price * tokenReserves[token] * (10**decimals())  / (10**tokenDecimals);
    }

    return aum;
  }
}
