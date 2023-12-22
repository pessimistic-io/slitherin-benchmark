// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./draft-ERC20Permit.sol";

contract xPOP is
  Ownable,
  ERC20("Popcorn.Network (Redeemable POP)", "xPOP"),
  ERC20Burnable,
  ERC20Permit("Popcorn.Network (Redeemable POP)")
{
  uint256 private immutable _mintCap;
  uint256 private _totalMinted;

  constructor(uint256 mintCap_) {
    require(mintCap_ > 0, "Mint cap is 0");
    _mintCap = mintCap_;
  }

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }

  function totalMinted() public view returns (uint256) {
    return _totalMinted;
  }

  function mintCap() public view returns (uint256) {
    return _mintCap;
  }

  function _mint(address to, uint256 amount) internal override {
    require(_totalMinted + amount <= mintCap(), "Mint cap exceeded");
    _totalMinted += amount;
    super._mint(to, amount);
  }
}

