// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./ContextUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PlennyBaseUpgradableV2.sol";

/// @title  Base abstract pausable contract.
/// @notice Used by all Plenny contracts, except PlennyERC20, to allow pausing of the contracts by addresses having PAUSER role.
/// @dev    Abstract contract that any Plenny contract extends from for providing pausing features.
abstract contract PlennyBasePausableV2 is PlennyBaseUpgradableV2, PausableUpgradeable {

    /// @notice PAUSER role constant
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev    Checks if the sender has PAUSER role.
    modifier onlyPauser() {
        require(hasRole(PAUSER_ROLE, _msgSender()), "ERR_NOT_PAUSER");
        _;
    }

    /// @notice Assigns PAUSER role for the given address.
    /// @dev    Only a pauser can assign more PAUSER roles.
    /// @param  account Address to assign PAUSER role to
    function addPauser(address account) external onlyPauser {
        _setupRole(PAUSER_ROLE, account);
    }

    /// @notice Renounces PAUSER role.
    /// @dev    The users renounce the PAUSER roles themselves.
    function renouncePauser() external {
        revokeRole(PAUSER_ROLE, _msgSender());
    }

    /// @notice Pauses the contract if not already paused.
    /// @dev    Only addresses with PAUSER role can pause the contract
    function pause() external onlyPauser whenNotPaused {
        _pause();
    }

    /// @notice Unpauses the contract if already paused.
    /// @dev    Only addresses with PAUSER role can unpause
    function unpause() external onlyPauser whenPaused {
        _unpause();
    }

    /// @notice Initializes the contract along with the PAUSER role.
    /// @param  _registry Contract registry
    function __plennyBasePausableInit(address _registry) internal initializer {
        PlennyBaseUpgradableV2.__plennyBaseInit(_registry);
        PausableUpgradeable.__Pausable_init();
        _setupRole(PAUSER_ROLE, _msgSender());
    }
}

