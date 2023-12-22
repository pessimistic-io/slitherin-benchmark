// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./Ownable.sol";
import "./IVaultManager.sol";
import "./IVault.sol";
contract VaultManager is IVaultManager, Ownable {
    address public immutable timelock;
    mapping(address => IVaultManager.VaultDetail) public Vault;

    constructor(address _timelock) public {
        require(_timelock != address(0), "Zero Address");
        timelock = _timelock;
    }

    modifier onlyTimelock() {
        require(msg.sender == timelock, "Call must come from timelock");
        _;
    }

    function addVaultAddress(
        address lpToken,
        address vault
    ) external override onlyOwner {
        require(IVault(vault).asset() == lpToken, "lpToken!=Vault's Asset");
        Vault[lpToken].vault = vault;
        Vault[lpToken].status = true;
        emit VaultAdded(lpToken, vault);
    }

    function emergencyPause(address vault) external override onlyTimelock {
        IVault(vault).pauseAndWithdraw();
        emit Status(vault, false);
    }

    function unpauseVaultAndDepost(
        address vault
    ) external override onlyTimelock {
        IVault(vault).unpauseAndDeposit();
        emit Status(vault, true);
    }

    function pauseVault(address vault) external override onlyTimelock {
        IVault(vault).pauseVault();
    }

    function unpauseVault(address vault) external override onlyTimelock {
        IVault(vault).unpauseVault();
    }

    function changeAllowance(
        address token,
        address to,
        address vault
    ) external override onlyTimelock {
        IVault(vault).changeAllowance(token, to);
    }
}

