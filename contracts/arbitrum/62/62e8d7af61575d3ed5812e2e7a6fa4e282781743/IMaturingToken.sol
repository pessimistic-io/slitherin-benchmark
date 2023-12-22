// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;
import "./ERC20_IERC20.sol";

interface IMaturingToken is IERC20 {
    function maturity() external view returns (uint256);
}
