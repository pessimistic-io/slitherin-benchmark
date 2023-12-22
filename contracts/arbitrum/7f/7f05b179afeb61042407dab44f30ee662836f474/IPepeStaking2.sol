//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPepeStaking } from "./IPepeStaking.sol";
import { Stake } from "./Structs.sol";

interface IPepeStaking2 is IPepeStaking {
    function accumulatedUsdcPerPeg() external view returns (uint256);

    function userStake(address user) external view returns (Stake memory);

    function totalStaked() external view returns (uint256);
}

