// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IERC20Minter is IERC20 {
  function mint(
    address recipient,
    uint256 amount
  )
    external;

  function burn(
    address account,
    uint256 amount
  )
    external;

    function getCurrentTokenId() external;
    function getNextTokenID() external;
}


