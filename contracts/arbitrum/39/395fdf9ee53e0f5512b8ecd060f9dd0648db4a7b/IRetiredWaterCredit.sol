// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRetiredWaterCredit {
    struct RetirementParams {
        address minter;
        address from;
        address receiver;
        uint amount;
        uint timestamp;
    }

    event WaterCreditRetired(uint tokenId, RetirementParams params);

    function retire(address from, address to, uint retiredAmount) external;
}

