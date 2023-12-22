// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControlEnumerable.sol";
import "./IVaultsFactory.sol";
import "./Vault.sol";

contract VaultsFactory is IVaultsFactory, AccessControlEnumerable {
    address public immutable weth;

    uint256 public unwrapDelay;

    address public feeReceiver;
    uint256 public feeBasisPoints;

    mapping(IVault => bool) public isVault;

    mapping(IVault => bool) public pausedVaults;
    bool public allVaultsPaused = false;

    // Role identifiers for pausing, deploying, and admin actions
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant TEAM_ROLE = keccak256("TEAM_ROLE");

    event VaultDeployed(IVault vaultAddress);
    event VaultPaused(IVault vaultAddress);
    event VaultUnpaused(IVault vaultAddress);
    event AllVaultsPaused();
    event AllVaultsUnpaused();

    constructor(
        address weth_,
        uint256 unwrapDelay_,
        address rolesAddr_,
        address initialFeeReceiver_,
        uint256 initialFeeBasisPoints_
    ) {
        require(weth_ != address(0), "VAULTS: ZERO_ADDRESS");

        weth = weth_;
        unwrapDelay = unwrapDelay_;

        _setupRole(DEFAULT_ADMIN_ROLE, rolesAddr_);
        _setupRole(PAUSE_ROLE, rolesAddr_);
        _setupRole(TEAM_ROLE, rolesAddr_);

        _setFeeReceiver(initialFeeReceiver_);
        _setFeeBasisPoints(initialFeeBasisPoints_);
    }

    function deployVault(IERC20Metadata underlyingToken_, string memory name_, string memory symbol_) external onlyRole(TEAM_ROLE) returns (IVault result) {
        result = new Vault(
            underlyingToken_,
            this,
            address(underlyingToken_) == weth,
            bytes(name_).length != 0 ? name_ : string(abi.encodePacked("Vaulted ", underlyingToken_.symbol())),
            bytes(symbol_).length != 0 ? symbol_ : string(abi.encodePacked("v", underlyingToken_.symbol()))
        );

        isVault[result] = true;

        emit VaultDeployed(result);
    }

    function pauseVault(IVault vault_) external onlyRole(PAUSE_ROLE) {
        require(isVault[vault_], "VAULTS: NOT_VAULT");

        pausedVaults[vault_] = true;
        emit VaultPaused(vault_);
    }

    function unpauseVault(IVault vault_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isVault[vault_], "VAULTS: NOT_VAULT");

        delete pausedVaults[vault_];
        emit VaultUnpaused(vault_);
    }

    function pauseAllVaults() external onlyRole(PAUSE_ROLE) {
        allVaultsPaused = true;
        emit AllVaultsPaused();
    }

    function unpauseAllVaults() external onlyRole(DEFAULT_ADMIN_ROLE) {
        allVaultsPaused = false;
        emit AllVaultsUnpaused();
    }

    function isPaused(IVault vault_) public view returns (bool) {
        return allVaultsPaused || pausedVaults[vault_];
    }

    function setUnwrapDelay(uint256 unwrapDelay_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        unwrapDelay = unwrapDelay_;
    }

    function emergencyWithdrawAddress() external view returns (address addr_) {
        addr_ = getRoleMember(DEFAULT_ADMIN_ROLE, 0);
        require(addr_ != address(0), "VAULTS: BROKEN_LOGIC");
    }

    function emergencyWithdrawFromVault(IVault vault_, uint256 amount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vault_.emergencyWithdraw(amount_);
    }

    function _setFeeReceiver(address feeReceiver_) internal {
        feeReceiver = feeReceiver_;
    }

    function _setFeeBasisPoints(uint256 feeBasisPoints_) internal {
        require(feeBasisPoints_ <= 200, "VAULTS: EXCESSIVE_FEE_PERCENT");  // Max 2%
        feeBasisPoints = feeBasisPoints_;
    }

    function setFeeReceiver(address feeReceiver_) external onlyRole(TEAM_ROLE) {
        _setFeeReceiver(feeReceiver_);
    }

    function setFeeBasisPoints(uint256 feeBasisPoints_) external onlyRole(TEAM_ROLE) {
        _setFeeBasisPoints(feeBasisPoints_);
    }
}

