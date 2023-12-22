// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./TransferHelper.sol";
import "./ISingleLP.sol";
import "./IDipxStorage.sol";
import "./IPositionManager.sol";
import "./IVaultPriceFeed.sol";

contract SingleLP is ERC20, ISingleLP{
  mapping (address => bool) public override isMinter;
  address public override token;
  bool isNativeCurrency;
  uint8 immutable tokenDecimals;

  modifier onlyMinter(){
    require(isMinter[msg.sender], "onlyMinter");
    _;
  }

  receive() external payable{
    require(isNativeCurrency);
  }

  constructor(address _token,bool _isNativeCurrency, string memory _name, uint8 _decimals) ERC20(_name,_name){
    token = _token;
    isNativeCurrency = _isNativeCurrency;
    isMinter[msg.sender] = true;
    tokenDecimals = _decimals;
  }

  function decimals() public view override(ERC20,IERC20Metadata) returns (uint8) {
    return tokenDecimals;
  }
  function isMixed() public override pure returns(bool){
    return false;
  }
  function tokenReserve() public override view returns(uint256){
    if(isNativeCurrency){
      return address(this).balance;
    }else{
      return IERC20(token).balanceOf(address(this));
    }
  }

  function setMinter(address _minter, bool _active) external override onlyMinter{
    isMinter[_minter] = _active;
  }

  function mint(address _to, uint256 _amount) external override onlyMinter{
    _mint(_to, _amount);
  }

  function withdraw(address _to, uint256 _amount) external override onlyMinter{
    require(tokenReserve()>=_amount, "Insufficient");
    if(isNativeCurrency){
      TransferHelper.safeTransferETH(_to, _amount);
    }else{
      TransferHelper.safeTransfer(token, _to, _amount);
    }
  }

  function burn(uint256 amount) public override {
    _burn(msg.sender, amount);
  }

  function burnFrom(address account, uint256 amount) public override {
    _spendAllowance(account, msg.sender, amount);
    _burn(account, amount);
  }

  function getPrice(address _dipxStorage, bool _includeProfit, bool _includeLoss) public override view returns(uint256){
    uint256 totalSupply = getSupplyWithPnl(_dipxStorage, _includeProfit, _includeLoss);
    uint256 pricePrecision = 10**IVaultPriceFeed(IDipxStorage(_dipxStorage).priceFeed()).decimals();
    
    if(totalSupply>0){
      return pricePrecision * tokenReserve()/totalSupply;
    }else{
      return 1*pricePrecision;
    }
  }

  function getSupplyWithPnl(address _dipxStorage, bool _includeProfit, bool _includeLoss) public view override returns(uint256){
    IPositionManager positionManager = IPositionManager(IDipxStorage(_dipxStorage).positionManager());
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

    uint256 supply = totalSupply() + totalProfit;
    if(supply >= totalLoss){
      supply = supply - totalLoss;
    }else{
      supply = 0;
    }
    
    return supply;
  }
}
