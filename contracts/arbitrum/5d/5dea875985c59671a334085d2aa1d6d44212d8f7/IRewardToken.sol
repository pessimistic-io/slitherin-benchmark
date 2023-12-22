// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC20 } from "./IERC20.sol";

interface IRewardToken is IERC20 {

    function mint(address to, uint256 amount) external;

    function transferReward(address to, uint256 amount) external returns (bool);

    function decimals() external view returns (uint8);
    
}
