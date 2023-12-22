// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IFundDeployer {
    function createNewFund(
        address,
        string memory,
        string memory,
        address,
        uint256,
        bytes memory,
        bytes memory
    ) external returns (address, address);
}

