// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8;

import "./ERC20.sol";
import "./draft-ERC20Permit.sol";
import "./Ownable.sol";

contract Token is ERC20, ERC20Permit, Ownable {
  constructor() ERC20("MAG", "MAG") ERC20Permit("MAG") {}

  function mint(address[] memory _to, uint256[] memory _amount) public onlyOwner {
    for(uint256 i = 0; i < _to.length; i++) {
      _mint(_to[i], _amount[i]);
    }
  }
}
