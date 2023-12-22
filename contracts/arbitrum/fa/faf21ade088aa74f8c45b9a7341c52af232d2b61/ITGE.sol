//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { User, Milestone } from "./Structs.sol";

interface ITGE {
    function donateUSDC(uint256 amount) external;

    function donatePLS(uint256 amount) external;

    function startSale() external;

    function stopSale() external;

    function pauseDonation() external;

    function unPauseDonation() external;

    function withdrawUSDC() external;

    function withdrawPLS() external;

    function getUsersPerMilestone(uint8 milestone) external view returns (User[] memory);

    function getUserDetails(address user) external view returns (User memory);

    function currentMilestone() external view returns (uint8);
}

