// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

interface VaultContract {
    function initialize(
        string memory _vaultId,
        address[] memory _whitelistAddresses,
        uint256 _minimumInvestmentAmount,
        address _factory
    ) external;
}

