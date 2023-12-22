// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./AccessControlEnumerable.sol";

import "./IVaultDeployer.sol";
import "./IPaymentModule.sol";
import "./FungibleVestingVault.sol";
import "./MultiVault.sol";
import "./IVaultKey.sol";

contract VaultDeployer is IVaultDeployer, AccessControlEnumerable {
    enum VaultStatus {
        Inactive,
        Locked,
        Unlocked
    }

    IVaultKey public immutable keyNFT;
    address public vaultFactory;

    event VaultFactoryUpdated(address indexed oldFactory, address indexed newFactory);

    constructor(address keyNFTAddress) {
        keyNFT = IVaultKey(keyNFTAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function createVestingVault(
        bool shouldMintKey,
        address beneficiary,
        uint256 unlockTimestamp,
        IDepositHandler.FungibleTokenDeposit[] memory fungibleTokenDeposits
    ) external override onlyFromFactory returns (address) {
        uint256 keyId = 0;
        if (shouldMintKey) {
            keyNFT.mintKey(beneficiary);
            keyId = keyNFT.lastMintedKeyId(beneficiary);
        }
        FungibleVestingVault vault = new FungibleVestingVault(vaultFactory, address(keyNFT), keyId, beneficiary, unlockTimestamp, fungibleTokenDeposits);
        return address(vault);
    }

    function createBatchVault(
        bool shouldMintKey,
        address beneficiary,
        uint256 unlockTimestamp,
        IDepositHandler.FungibleTokenDeposit[] memory fungibleTokenDeposits,
        IDepositHandler.NonFungibleTokenDeposit[] memory nonFungibleTokenDeposits,
        IDepositHandler.MultiTokenDeposit[] memory multiTokenDeposits
    ) external override onlyFromFactory returns (address) {
        uint256 keyId = 0;
        if (shouldMintKey) {
            keyNFT.mintKey(beneficiary);
            keyId = keyNFT.lastMintedKeyId(beneficiary);
        }
        MultiVault vault = new MultiVault(
            vaultFactory,
            address(keyNFT),
            keyId,
            beneficiary,
            unlockTimestamp,
            fungibleTokenDeposits,
            nonFungibleTokenDeposits,
            multiTokenDeposits
        );
        return address(vault);
    }

    function updateVaultFactory(address newFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit VaultFactoryUpdated(vaultFactory, newFactory);
        vaultFactory = newFactory;
    }

    modifier onlyFromFactory() {
        require(msg.sender == vaultFactory, "VaultDeployer: Only callable from factory");
        _;
    }
}

