// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IMintableERC20.sol";
import "./IVault.sol";
import "./IPositionManager.sol";
import "./ILpManager.sol";
import "./IDipxStorage.sol";
import "./TransferHelper.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract Vault is Initializable,OwnableUpgradeable,IVault{
  mapping(address => bool) public isMinter;

  address public dipxStorage;

  modifier onlyMinter(){
    require(isMinter[msg.sender], "FORBIDDEN");
    _;
  }

  constructor(){
  }

  function initialize(address _dipxStorage) public initializer{
    __Ownable_init();
    dipxStorage = _dipxStorage;
  }

  function setDipxStorage(address _dipxStorage) external override onlyOwner{
    dipxStorage = _dipxStorage;
  }

  function setMinter(address _minter, bool _active) external override onlyOwner{
    isMinter[_minter] = _active;
  }
  
  function adjustForDecimals(uint256 _value, uint256 _tokenDiv, uint256 _tokenMul) public pure returns(uint256){
    return _value * (10**_tokenMul) / (10**_tokenDiv);
  }

  function transferOut(address _token, address _to, uint256 _amount) external override onlyMinter{
    TransferHelper.safeTransfer(_token, _to, _amount);
  }

  function mint(address _token, uint256 _amount) external override onlyMinter{
    IMintableERC20(_token).mint(address(this), _amount);
  }
  function burn(address _token, uint256 _amount) external override onlyMinter{
    IMintableERC20(_token).burn(_amount);
  }
}
