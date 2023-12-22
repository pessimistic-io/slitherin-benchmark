// SPDX-License-Identifier: AGPL

pragma solidity ^0.8.13;

library StructContribution {
    struct Contribution {
        address contributer;
        uint256 amount;
        uint256 timestamp;
    }
}

interface IPrivateContribution {
    function endTime() external returns (uint256);

    function getAllContributions() external view returns (StructContribution.Contribution[] memory);
}

