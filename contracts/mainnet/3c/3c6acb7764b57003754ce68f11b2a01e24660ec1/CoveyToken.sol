// contracts/CoveyToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20Burnable.sol";
import "./ERC20.sol";
import "./Ownable.sol";


contract CoveyToken is ERC20, ERC20Burnable, Ownable {
  uint256 public constant _maxSupply = 1_000_000 * 1e18;

  constructor() ERC20("Covey", "CVY")  {}

  function mint(
    address account,
    uint256 amount) external onlyOwner {
      require(totalSupply() + amount <= _maxSupply, "Token Minting cannot exceed Max Supply");
      _mint(account, amount);
  }

}
