// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./ContextUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./IContractRegistry.sol";

/// @title  Base Plenny upgradeable contract.
/// @notice Used by all Plenny contracts, except PlennyERC20, to allow upgradeable contracts.
abstract contract PlennyBaseUpgradableV2 is AccessControlUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {

    /// @notice Plenny contract addresses registry
    IContractRegistry public contractRegistry;

    /// @notice Initializes the contract. Can be called only once.
    /// @dev    Upgradable contracts does not have a constructor, so this method is its replacement.
    /// @param  _registry Plenny contracts registry
    function __plennyBaseInit(address _registry) internal initializer {
        require(_registry != address(0x0), "ERR_REG_EMPTY");
        contractRegistry = IContractRegistry(_registry);

        AccessControlUpgradeable.__AccessControl_init();
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @notice Returns current block number
    /// @return uint256 block number
    function _blockNumber() internal view returns (uint256) {
        return block.number;
    }
}

