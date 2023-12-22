// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract POOH is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("POOH", "POOH") {
    address wallet = 0x5e58c97F781f98d70F9b72e69629312bF70EBaf4;

    _mint(wallet, 420690000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

