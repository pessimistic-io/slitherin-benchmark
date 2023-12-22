// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

import "./ERC20.sol";

contract AlphaGAZER is ERC20 {
    using SafeMath for uint256;
  
    address public minter;
    bool public initialized;

    constructor(address _minter) ERC20("AlphaGAZER", "aGAZER", 9) {
      require(_minter != address(0), "Minter cannot be empty");
      minter = _minter;
    }

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }

    function initialize(address _to) external {
      require(msg.sender == minter, "Sender is not minter");
      require(!initialized, "aGAZER already initialized");
      initialized = true;
      _mint(_to, 3_000_000_000_000_000); //Total Supply is 3M
    }
}
