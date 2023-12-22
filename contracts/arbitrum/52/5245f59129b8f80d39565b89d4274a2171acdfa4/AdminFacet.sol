// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
import "./LibStorage.sol";
import {LibAccessControl} from "./LibAccessControl.sol";
import {ERC1155MetadataStorage} from "./ERC1155MetadataStorage.sol";

contract AdminFacet is WithStorage, WithModifiers {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice Sets the cost to buy a founder's pack
    /// @param cost Dollar cost x1000 (e.g 15500 = $15.5)
    function setFoundersPackUsdCost(uint32 cost)
        external
        roleOnly(LibAccessControl.Roles.ADMIN)
    {
        require(cost > 0, "AdminFacet: Cost cannot be 0");

        _ss().foundersPackUsdCost = cost;
    }

    /// @notice Sets the extra native token cost charged to cover minting gas cost
    /// @param offset Offset in wei
    function setFoundersPackGasOffset(uint256 offset)
        external
        roleOnly(LibAccessControl.Roles.ADMIN)
    {
        _ss().foundersPackGasOffset = offset;
    }

    /// @notice Sets the extra nft withdrawal cost charged to cover gas costs
    /// @param offset Offset in wei
    function setWithdrawalGasOffset(uint256 offset)
        external
        roleOnly(LibAccessControl.Roles.ADMIN)
    {
        _ts().withdrawalGasOffset = offset;
    }

    /// @notice Gets roles assigned to an address
    /// @param user Address to set role to
    function getRoles(address user) external view returns (uint256[] memory) {
        uint256 length = _acs().rolesByAddress[user].length();
        uint256[] memory values = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            values[i] = _acs().rolesByAddress[user].at(i);
        }

        return values;
    }

    /// @notice Assigns a role to an address
    /// @param recipient Address to set role to
    /// @param role Role to assign
    function setRole(address recipient, LibAccessControl.Roles role)
        external
        ownerOnly
    {
        require(
            !_acs().rolesByAddress[recipient].contains(uint256(role)),
            "Role already set"
        );
        _acs().rolesByAddress[recipient].add(uint256(role));
    }

    /// @notice Revokes a role from an address
    /// @param recipient Address to set role to
    /// @param role Role to assign
    function revokeRole(address recipient, LibAccessControl.Roles role)
        external
        ownerOnly
    {
        require(
            _acs().rolesByAddress[recipient].contains(uint256(role)),
            "Role not set"
        );
        _acs().rolesByAddress[recipient].remove(uint256(role));
    }

    function pauseContract(bool paused)
        external
        roleOnly(LibAccessControl.Roles.ADMIN)
    {
        _acs().paused = paused;
    }

    function getIsContractPaused() external view returns (bool) {
        return _acs().paused;
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function transferContractFunds(uint256 funds)
        external
        roleOnly(LibAccessControl.Roles.ADMIN)
    {
        require(
            _acs().contractFundsRecipient != address(0),
            "Contract Funds recipient is the zero address"
        );
        payable(_acs().contractFundsRecipient).transfer(funds);
    }

    function _setRoyalties(address newRecipient) internal {
        require(
            newRecipient != address(0),
            "Royalties: new recipient is the zero address"
        );
        _ts().royaltiesRecipient = newRecipient;
    }

    function setRoyalties(address newRecipient) external ownerOnly {
        _setRoyalties(newRecipient);
    }

    function setFoundersPackPurchaseAllowed(bool allowed)
        external
        roleOnly(LibAccessControl.Roles.ADMIN)
    {
        _ss().foundersPackPurchaseAllowed = allowed;
    }

    /// @notice Sets a new forger address, remember to set and revoke roles as well
    /// @param newForger Address to set as forger address
    function setForgerAddress(address newForger) external ownerOnly {
        _acs().forgerAddress = newForger;
    }

    /// @notice Sets a new boris address, remember to set and revoke roles as well
    /// @param newBoris Address to set as forger address
    function setBorisAddress(address newBoris) external ownerOnly {
        _acs().borisAddress = newBoris;
    }

    function getForgerBalance() external view returns (uint256) {
        return address(_acs().forgerAddress).balance;
    }

    function getBorisBalance() external view returns (uint256) {
        return address(_acs().borisAddress).balance;
    }

    function getBotsFeePercentage() external view returns (uint256) {
        return _ss().botsFeePercentage;
    }

    function setBotsFeePercentage(uint256 feePercentage)
        external
        roleOnly(LibAccessControl.Roles.ADMIN)
    {
        require(feePercentage > 0, "Fee percentage must be > 0");

        _ss().botsFeePercentage = feePercentage;
    }
}

