// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./TransferHelper.sol";
import "./Math.sol";
import "./IDIPX.sol";
import "./OwnableUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./console.sol";

contract veDIPX is ERC20Upgradeable,ERC20BurnableUpgradeable,OwnableUpgradeable{
  address public dipx;
  bool public inPrivateTransferMode;
  mapping(address => bool) public isHandler;
  mapping(address => bool) public isMinter;
  mapping(address => bool) public isVestor;
  uint256 public constant MAX_SUPPLY = 1000_000_000e18; // DIPX + veDIPX

  modifier onlyMinter() {
    require(isMinter[msg.sender], "veDIPX: forbidden");
    _;
  }

  function initialize(address _dipx, string memory _name, string memory _symbol) initializer public {
    __ERC20_init(_name, _symbol);
    __ERC20Burnable_init();
    __Ownable_init();

    dipx = _dipx;
  }

  function mint(address to, uint256 value) public onlyMinter{
    _mint(to, value);
    uint256 dipxSupply = IDIPX(dipx).totalSupply();
    require(totalSupply() + dipxSupply <= MAX_SUPPLY, "supply exceed");
  }

  function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyOwner {
    inPrivateTransferMode = _inPrivateTransferMode;
  }
  function setHandler(address _handler, bool _active) external onlyOwner {
    isHandler[_handler] = _active;
  }
  function setMinter(address _minter, bool _active) external onlyOwner {
    isMinter[_minter] = _active;
  }
  function setVestor(address _vestor, bool _active) external onlyOwner {
    isVestor[_vestor] = _active;
  }

  function vest(address _account, uint256 _value) public{
    require(isVestor[msg.sender], "veDIPX: vest forbidden");

    IDIPX(dipx).mint(_account, _value);
    _burn(msg.sender,_value);
  }
  
  function _beforeTokenTransfer(address /*from*/, address /*to*/, uint256 /*amount*/) internal view override{
    if (inPrivateTransferMode) {
      require(isHandler[msg.sender], "veDIPX: msg.sender not whitelisted");
    }
  }
}
