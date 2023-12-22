// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./AccessControl.sol";
import "./Pausable.sol";

contract RelativeTestUSD is ERC20, ERC20Burnable, Pausable, AccessControl {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");

  uint256 public waitTime = 24 hours;
  uint256 public dripAmount = 10000 * 1e6;

  mapping(address => uint256) lastDripTime;

  constructor() ERC20("RelativeTestUSD", "RUSD") {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);
    // allow minting and buring of tokens
    _setupRole(TRANSFER_ROLE, address(0));
  }

  function decimals() public pure override returns (uint8) {
    return 6;
  }

  function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
  }

  function grantMinterRole(address _minter)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    grantRole(MINTER_ROLE, _minter);
  }

  function revokeMinterRole(address _minter)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    revokeRole(MINTER_ROLE, _minter);
  }

  function grantTransferRole(address _transferer)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    grantRole(TRANSFER_ROLE, _transferer);
  }

  function revokeTransferRole(address _transferer)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    revokeRole(TRANSFER_ROLE, _transferer);
  }

  function mint(address _to, uint256 _amount) public onlyRole(MINTER_ROLE) {
    _mint(_to, _amount);
  }

  function setWaitTime(uint256 _waitTime) public onlyRole(DEFAULT_ADMIN_ROLE) {
    waitTime = _waitTime;
  }

  function setDripAmount(uint256 _dripAmount) public onlyRole(DEFAULT_ADMIN_ROLE) {
    dripAmount = _dripAmount;
  }

  function faucetDrip() public whenNotPaused {
    require(allowedToDrip(msg.sender));
    _mint(msg.sender, dripAmount);
    lastDripTime[msg.sender] = block.timestamp + waitTime;
  }

  function allowedToDrip(address _address) public view returns (bool) {
    if(lastDripTime[_address] == 0) {
      return true;
    } else if (block.timestamp >= lastDripTime[_address]) {
      return true;
    }
    return false;
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override whenNotPaused {
    require(
      hasRole(TRANSFER_ROLE, from) || hasRole(TRANSFER_ROLE, to),
      "transfer not allowed!"
    );

    super._beforeTokenTransfer(from, to, amount);
  }
}
