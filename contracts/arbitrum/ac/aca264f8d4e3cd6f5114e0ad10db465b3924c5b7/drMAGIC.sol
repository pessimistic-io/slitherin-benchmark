// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC20.sol";
import "./AccessControl.sol";

import "./IERC20Mintable.sol";

/**
 * @title drMAGIC
 * @author kvk0x
 *
 * drMAGIC is a wrapped version of MAGIC, similar to cvxCRV in the Convex/Curve
 * ecosystem. drMAGIC can be looked at as the "entry ticket" to capturing emissions
 * from MDD's yield-generating activities. drMAGIC can be staked to earn blended yield,
 * or LP'd with MAGIC to earn farming rewards.
 *
 */
contract drMAGIC is ERC20, IERC20Mintable, AccessControl {
    // ============================================ ROLES ==============================================

    /// @dev Contract owner. Allowed to update access to other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @dev Role allowing minting of tokens. Will be granted to depositor contract.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @dev Role allowing burning of tokens. Not currently used, but may be in the future
    ///      (e.g. for a hypothetical MAGIC redemption).
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // ========================================== CONSTRUCTOR ===========================================

    /**
     * @notice Initializes the roles of the contract, with a defined administrator,
     *         who is allowed to set other administrators, minters, and burners.
     */
    constructor() ERC20("Dragon MAGIC", "drMAGIC") {
        _setupRole(ADMIN_ROLE, msg.sender);

        // Allow only admins to change other roles
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BURNER_ROLE, ADMIN_ROLE);
    }

    // ======================================== TOKEN OPERATIONS ========================================

    /**
     * @notice Mint new tokens. Can only be called by a designated minter.
     * @dev    Per ERC20 spec, emits a Transfer event.
     *
     * @param _to                   The address to receive newly-minted tokens.
     * @param _amount               The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }

    /**
     * @notice Burn tokens. Can only be called by a designated burner.
     * @dev    Per ERC20 spec, emits a Transfer event.
     *
     * @param _from                 The address from which to debit burned tokens.
     * @param _amount               The amount of tokens burn mint.
     */
    function burn(address _from, uint256 _amount) external onlyRole(BURNER_ROLE) {
        _burn(_from, _amount);
    }
}

