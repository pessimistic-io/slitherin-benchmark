// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IAccessControl } from "./IAccessControl.sol";
import { IERC20 } from "./IERC20.sol";

interface IPreHYPS is IERC20, IAccessControl {
    /**
     * @dev A structure to communicate single mint request in batch minting transaction.
     * @param account The account which receives the tokens.
     * @param amount The amount of minted tokens.
     */
    struct Mint {
        address account;
        uint256 amount;
    }

    /**
     * @dev A structure to communicate single burn request in batch burning transaction.
     * @param account The account which held the tokens.
     * @param amount The amount of burned tokens.
     */
    struct Burn {
        address account;
        uint256 amount;
    }

    /**
     * @notice Emitted when the new soft cap is set.
     * @param softCap The new soft cap value.
     */
    event SoftCapSet(uint256 softCap);

    /**
     * @notice Emitted when `account` swaps PreHYPS to HYPS.
     * @param account The account that initiated the swap.
     * @param amount The amount of swapped tokens.
     */
    event Swapped(address indexed account, uint256 amount);

    /**
     * @notice Emitted when the PreHYPS supply is frozen prior to HYPS distribution.
     * @param totalSupply The PreHYPS total supply.
     */
    event SupplyFrozen(uint256 totalSupply);

    /**
     * @notice Emitted when the PreHYPS -> HYPS swapping is enabled.
     */
    event SwappingEnabled();

    /**
     * @notice Increases the soft cap by `amount`.
     * @dev Can only be called by an admin.
     * @param amount The amount to increase the soft cap by.
     */
    function incrementSoftCapBy(uint256 amount) external;

    /**
     * @notice Swaps PreHYPS tokens to HYPS tokens.
     * @dev Can only be called after the swapping is enabled.
     * @dev Can only be called by a token holder.
     */
    function swap() external;

    /**
     * @notice Freezes the PreHYPS supply.
     * @dev Can only be called by an admin.
     */
    function freezeSupply() external;

    /**
     * @dev Enables swapping. Allows token holders to swap PreHYPS -> HYPS.
     * @dev Can only be called after the supply is frozen.
     * @param hyps The address of the HYPS token.
     */
    function enableSwapping(IERC20 hyps) external;

    /**
     * @notice Mints `amount` of tokens to `account`.
     * @dev Can only be called by a minter.
     * @param account The account which receives the tokens.
     * @param amount The amount of tokens to be minted.
     */
    function mintTo(address account, uint256 amount) external;

    /**
     * @notice Bulk minting. For every element in the `mintList`, mints specified `amount` of tokens to the corresponding `account`.
     * @dev Can only be called by a minter.
     * @param mintList The list of mint requests.
     */
    function mintToMany(Mint[] calldata mintList) external;

    /**
     * @notice Burns `amount` of tokens from `account`.
     * @dev Can only be called by an admin.
     * @param account The account which held the tokens.
     * @param amount The amount of tokens to be burned.
     */
    function burnFrom(address account, uint256 amount) external;

    /**
     * @notice Bulk burning. For every element in the `burnList`, burns specified `amount` of tokens from the corresponding `account`.
     * @dev Can only be called by an admin.
     * @param burnList The list of burn requests.
     */
    function burnFromMany(Burn[] calldata burnList) external;

    /**
     * @notice Recovers ERC20 tokens from the contract.
     * @dev Can only be called by an admin.
     * @param token The address of the ERC20 token to recover.
     * @param amount The amount of tokens to recover.
     * @param to The address to which the recovered tokens are sent.
     */
    function recoverERC20(address token, uint256 amount, address to) external;

    /**
     * @notice Returns true when the PreHYPS supply can no longer be changed.
     * @dev After the supply is frozen, the minting and burning are disabled.
     */
    function supplyFrozen() external view returns (bool);

    /**
     * @notice Returns true when the PreHYPS token holders can swap their tokens to HYPS.
     * @dev The swapping can be enabled only when the supply is frozen.
     */
    function swappingEnabled() external view returns (bool);

    /**
     * @notice Returns current soft cap value.
     */
    function softCap() external view returns (uint256);

    /**
     * @notice Returns the amount of tokens that can be minted before hitting the soft cap.
     */
    function availableForMinting() external view returns (uint256);
}

