// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

interface VaultContract {
    function initialize(
        uint256 _vaultId,
        address[] memory _privateWalletAddresses,
        address _vaultCreator,
        uint256 _minimumInvestmentAmount,
        address _factory
    ) external;
}

