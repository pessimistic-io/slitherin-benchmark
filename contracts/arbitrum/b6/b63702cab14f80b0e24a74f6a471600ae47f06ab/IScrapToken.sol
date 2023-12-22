
//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;
import "./IERC20.sol";

interface IScrapToken is IERC20 {
 
  function mint(uint256 amount, address receiver)
    external
    returns (uint256);
}

