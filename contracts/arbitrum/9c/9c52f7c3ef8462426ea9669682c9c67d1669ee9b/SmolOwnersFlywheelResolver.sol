// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./IERC721.sol";
import "./Initializable.sol";

import "./ICreatureOwnerResolver.sol";
import "./ISmolverseFlywheelVault.sol";

/**
 * @title  SmolOwnersFlywheelResolver contract
 * @author Archethect
 * @notice This contract contains all functionalities for verifying Smol ownership of Flywheel staked smols
 */
contract SmolOwnersFlywheelResolver is Initializable, ICreatureOwnerResolver {
    IERC721 public wrappedSmols;
    IERC721 public smols;
    ISmolverseFlywheelVault public smolverseFlywheelVault;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address smols_,
        address wrappedSmols_,
        address smolverseFlywheelVault_
    ) public initializer {
        require(address(smols_) != address(0), "SMOLOWNERSRESOLVERADAPTER:ILLEGAL_ADDRESS");
        require(address(wrappedSmols_) != address(0), "SMOLOWNERSRESOLVERADAPTER:ILLEGAL_ADDRESS");
        require(address(smolverseFlywheelVault_) != address(0), "SMOLOWNERSRESOLVERADAPTER:ILLEGAL_ADDRESS");
        smols = IERC721(smols_);
        wrappedSmols = IERC721(wrappedSmols_);
        smolverseFlywheelVault = ISmolverseFlywheelVault(smolverseFlywheelVault_);
    }

    function isOwner(address account, uint256 tokenId) external view override returns (bool) {
        if (smolverseFlywheelVault.isOwner(address(smols), tokenId, account)) {
            return true;
        } else {
            return smolverseFlywheelVault.isOwner(address(wrappedSmols), tokenId, account);
        }
    }
}

