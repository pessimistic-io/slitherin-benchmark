// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";

interface IFarmingLevelMasterV2 {
    function rewardToken() external view returns (IERC20);
    
    function lpToken(uint256 id) external view returns (address);
    
    function deposit(uint256 pid, uint256 amount, address to) external;

    function withdraw(uint256 pid, uint256 amount, address to) external;

    function harvest(uint256 pid, address to) external;
}
