// SPDX-License-Identifier: MIT

pragma solidity >0.6.0;

interface IVaultManager {
    struct VaultDetail {
        address vault;
        bool status;
    }
    event Status(address vault, bool isActive);
    event VaultAdded(address vault, address lpToken);

    function addVaultAddress(address lpToken, address vault) external;

    function changeAllowance(address token, address to, address vault) external;

    function emergencyPause(address vault) external;

    function unpauseVaultAndDepost(address vault) external;

    function pauseVault(address vault) external;

    function unpauseVault(address vault) external;
}

