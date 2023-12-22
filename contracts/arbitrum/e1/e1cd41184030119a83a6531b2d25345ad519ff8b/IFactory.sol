// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

interface FactoryContract {
    function acceptedToken() external view returns (address);

    function tradeFee() external view returns (uint256);

    function withdrawalFee() external view returns (uint256);

    function treasuryContractAddress() external view returns (address);

    function getVaultCreatorReward(
        address vaultCreator,
        uint tvl
    ) external view returns (uint64);
}

