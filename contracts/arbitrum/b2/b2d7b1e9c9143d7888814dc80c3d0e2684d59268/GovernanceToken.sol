// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20Votes.sol";

contract GovernanceToken is ERC20Votes {
  constructor() ERC20("GovernanceToken", "GT") ERC20Permit("GovernanceToken") {}

  function mintMe() public {
    _mint(msg.sender, 1e18);
  }

  // The functions below are overrides required by Solidity.

  function _afterTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override(ERC20Votes) {
    super._afterTokenTransfer(from, to, amount);
  }

  function _mint(address to, uint256 amount) internal override(ERC20Votes) {
    super._mint(to, amount);
  }

  function _burn(address account, uint256 amount) internal override(ERC20Votes) {
    super._burn(account, amount);
  }
}

