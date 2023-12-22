// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IExtendedSelfMulticall.sol";

interface IMerkleFunder is IExtendedSelfMulticall {
    event DeployedMerkleFunderDepository(
        address indexed merkleFunderDepository,
        address owner,
        bytes32 root
    );

    event Funded(
        address indexed merkleFunderDepository,
        address recipient,
        uint256 amount
    );

    event Withdrew(
        address indexed merkleFunderDepository,
        address recipient,
        uint256 amount
    );

    error RootZero();

    error RecipientAddressZero();

    error LowThresholdHigherThanHigh();

    error HighThresholdZero();

    error InvalidProof();

    error RecipientBalanceLargerThanLowThreshold();

    error NoSuchMerkleFunderDepository();

    error AmountZero();

    error InsufficientBalance();

    function deployMerkleFunderDepository(
        address owner,
        bytes32 root
    ) external returns (address payable merkleFunderDepository);

    function fund(
        address owner,
        bytes32 root,
        bytes32[] calldata proof,
        address recipient,
        uint256 lowThreshold,
        uint256 highThreshold
    ) external returns (uint256 amount);

    function withdraw(bytes32 root, address recipient, uint256 amount) external;

    function withdrawAll(
        bytes32 root,
        address recipient
    ) external returns (uint256 amount);

    function computeMerkleFunderDepositoryAddress(
        address owner,
        bytes32 root
    ) external view returns (address merkleFunderDepository);

    function ownerToRootToMerkleFunderDepositoryAddress(
        address owner,
        bytes32 root
    ) external view returns (address payable merkleFunderDepository);
}

