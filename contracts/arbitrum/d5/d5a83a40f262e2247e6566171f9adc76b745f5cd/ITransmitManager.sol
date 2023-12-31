// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface ITransmitManager {
    function checkTransmitter(
        uint32 siblingSlug,
        bytes32 digest,
        bytes calldata signature
    ) external view returns (address, bool);

    function payFees(uint32 dstSlug) external payable;

    function getMinFees(uint32 dstSlug) external view returns (uint256);

    function setProposeGasLimit(
        uint256 nonce_,
        uint256 dstChainSlug_,
        uint256 gasLimit_,
        bytes calldata signature_
    ) external;
}

