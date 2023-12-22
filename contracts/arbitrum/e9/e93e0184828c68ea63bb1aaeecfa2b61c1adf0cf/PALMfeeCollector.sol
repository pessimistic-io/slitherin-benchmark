// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import {     IArrakisV2 } from "./IArrakisV2.sol";
import {IPALMfeeCollector} from "./IPALMfeeCollector.sol";
import {IPALMManager} from "./IPALMManager.sol";
import {IPALMTerms} from "./IPALMTerms.sol";
import {     OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import {     IERC20,     SafeERC20 } from "./SafeERC20.sol";
import {VaultInfo} from "./SPALMManager.sol";

/// @title PALMfeeCollector automates the collection of management fees from PALM vaults
/// @author Bofan Ji
contract PALMfeeCollector is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address public immutable palmTermsAddr;

    event MaturedVaultsWithdrawn(address[] vaults, address[] tokens);
    event OwnershipInitialized(address owner);

    constructor(address palmTermsAddr_) {
        palmTermsAddr = palmTermsAddr_;
    }

    function initialize(address owner_) external initializer {
        require(
            owner_ != address(0),
            "PALMfeeCollector: owner is address zero"
        );
        _transferOwnership(owner_);
        emit OwnershipInitialized(owner_);
    }

    /// @notice Harvest fees from matured vaults, renew the vaults, and send fees to arrakisMultisig
    /// @param maturedVaults all vaults that are ready to be harvested
    /// @dev requires ownership of PALMManager to be transferred to this contract before calling
    function collectManagementFees(address[] memory maturedVaults) external {
        address[] memory tokensToCollect = new address[](
            maturedVaults.length * 2
        );
        uint256 maturedCount = 0;
        /// loop through vaults, withdraw manager fees, renew term, and add tokens to array
        for (uint256 i = 0; i < maturedVaults.length; i++) {
            IArrakisV2 palmVault = IArrakisV2(maturedVaults[i]);
            IPALMTerms(palmVault.owner()).renewTerm(palmVault);
            /// if renewTerm was successful, proceed with withdrawal
            palmVault.withdrawManagerBalance();
            address token0 = address(palmVault.token0());
            address token1 = address(palmVault.token1());
            tokensToCollect[i * 2] = token0;
            tokensToCollect[i * 2 + 1] = token1;
            maturedCount++;
        }
        /// if no vaults were renewed, revert the function
        require(maturedCount > 0, "PALMFeeCollector: No vault was mature");
        /// withdraw fees from manager contract to arrakisDAOOwner
        address managerAddr = IPALMTerms(palmTermsAddr).manager();
        address arrakisDAOOwner = IPALMTerms(palmTermsAddr).owner();
        IPALMManager(managerAddr).withdrawFeesEarned(
            tokensToCollect,
            arrakisDAOOwner
        );
        emit MaturedVaultsWithdrawn(maturedVaults, tokensToCollect);
    }

    /// @notice restore ownership of PALMManager to Multisig
    /// @param palmManager_ the address of PALMManager
    /// @param managerNewOwner_ the address of the new owner of PALMManager
    function restoreOwnership(address palmManager_, address managerNewOwner_)
        external
        onlyOwner
    {
        IPALMManager(palmManager_).transferOwnership(managerNewOwner_);
    }

    /// @notice Find and return all vaults that are ready to be harvested
    /// @param allVaults all PALM vaults
    /// @return canExec true if there are vaults ready to be harvested, false otherwise
    /// @return payload the hashed function call of collectManagementFees
    function checker(address[] calldata allVaults)
        external
        view
        returns (bool canExec, bytes memory payload)
    {
        (bool[] memory matured, uint256 maturedCount) = _getMaturedVaults(
            allVaults
        );
        if (maturedCount == 0) {
            return (false, bytes("nothing to do"));
        }
        address[] memory maturedVaults = new address[](maturedCount);
        uint256 index = 0;
        for (uint256 i = 0; i < matured.length; i++) {
            if (matured[i] == true) {
                maturedVaults[index] = allVaults[i];
                index++;
            }
        }
        bytes4 selector = IPALMfeeCollector.collectManagementFees.selector;
        payload = abi.encodeWithSelector(selector, maturedVaults);
        return (true, payload);
    }

    /// @notice private method to find all vaults that are ready to be harvested
    /// @param allVaults an array of addresses representing all the vaults to check for maturity
    /// @return maturedVaults an array of boolean values indicating which vaults have matured
    /// @return maturedCount a count of matured vaults
    function _getMaturedVaults(address[] memory allVaults)
        private
        view
        returns (bool[] memory maturedVaults, uint256 maturedCount)
    {
        maturedVaults = new bool[](allVaults.length);
        maturedCount = 0;
        for (uint256 i = 0; i < allVaults.length; i++) {
            address manager = IPALMTerms(palmTermsAddr).manager();
            VaultInfo memory vaultinfo = IPALMManager(manager).getVaultInfo(
                allVaults[i]
            );
            uint256 termEnd = vaultinfo.termEnd;
            if (block.timestamp >= termEnd) {
                maturedVaults[i] = true;
                maturedCount++;
            }
        }
        return (maturedVaults, maturedCount);
    }
}

