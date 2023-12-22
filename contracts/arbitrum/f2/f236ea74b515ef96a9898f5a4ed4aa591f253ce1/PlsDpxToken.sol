// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract PlsDpxToken is ERC20, Ownable {
  address public operator;

  constructor() ERC20('Plutus DPX', 'plsDPX') {}

  function mint(address _to, uint256 _amount) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _mint(_to, _amount);
  }

  function burn(address _from, uint256 _amount) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _burn(_from, _amount);
  }

  /** OWNER FUNCTIONS */
  function setOperator(address _operator) external onlyOwner {
    operator = _operator;
  }

  error UNAUTHORIZED();
}

