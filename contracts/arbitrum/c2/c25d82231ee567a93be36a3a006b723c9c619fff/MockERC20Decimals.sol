// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./ERC20.sol";

contract MockERC20Decimals is ERC20 {
  uint8 private _decimals;

  constructor(
    string memory _pName,
    string memory _pSymbol,
    uint8 _pDecimals,
    uint256 _pInitialSupply
  ) ERC20(_pName, _pSymbol) {
    _decimals = _pDecimals;
    _mint(msg.sender, _pInitialSupply * 10**uint256(_pDecimals));
  }

  /**
   * @dev Override ERC20 decimals
   */
  function decimals() public view override returns (uint8) {
    return _decimals;
  }
}

