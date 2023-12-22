// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

interface ITransmitManager {
    function checkTransmitter(
        uint32 siblingSlug,
        bytes32 digest,
        bytes calldata signature
    ) external view returns (address, bool);

    function sealGasLimit() external view returns (uint256);
}

