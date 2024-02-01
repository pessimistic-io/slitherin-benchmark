//SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

/// @title ETH Bridge Logic Interface
/// @author Vega Protocol
/// @notice Implementations of this interface are used by Vega network users to deposit and withdraw ETH to/from Vega.
// @notice All funds deposited/withdrawn are to/from the ETH_Asset_Pool
abstract contract IETH_Bridge_Logic {
    /***************************EVENTS****************************/
    event ETH_Withdrawn(address indexed user_address, uint256 amount, uint256 nonce);
    event ETH_Deposited(address indexed user_address, uint256 amount, bytes32 vega_public_key);
    event ETH_Deposit_Minimum_Set(uint256 new_minimum, uint256 nonce);
    event ETH_Deposit_Maximum_Set(uint256 new_maximum, uint256 nonce);

    /***************************FUNCTIONS*************************/
    /// @notice This function sets the minimum allowable deposit for ETH
    /// @param minimum_amount Minimum deposit amount
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @notice See MultisigControl for more about signatures
    /// @dev MUST emit Asset_Deposit_Minimum_Set if successful
    function set_deposit_minimum(
        uint256 minimum_amount,
        uint256 nonce,
        bytes memory signatures
    ) external virtual;

    /// @notice This function sets the maximum allowable deposit for ETH
    /// @param maximum_amount Maximum deposit amount
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @notice See MultisigControl for more about signatures
    /// @dev MUST emit Asset_Deposit_Maximum_Set if successful
    function set_deposit_maximum(
        uint256 maximum_amount,
        uint256 nonce,
        bytes memory signatures
    ) external virtual;

    /// @notice This function withdraws assets to the target Ethereum address
    /// @param amount Amount of ETH to withdraw
    /// @param expiry Vega-assigned timestamp of withdrawal order expiration
    /// @param target Target Ethereum address to receive withdrawn ETH
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @notice See MultisigControl for more about signatures
    /// @dev MUST emit Asset_Withdrawn if successful
    function withdraw_asset(
        uint256 amount,
        uint256 expiry,
        address payable target,
        uint256 nonce,
        bytes memory signatures
    ) external virtual;

    /// @notice This function allows a user to deposit ETH into Vega
    /// @param vega_public_key Target vega public key to be credited with this deposit
    /// @dev MUST emit Asset_Deposited if successful
    /// @dev ETH approve function should be run before running this
    /// @notice ETH approve function should be run before running this
    function deposit_asset(bytes32 vega_public_key) external payable virtual;

    /***************************VIEWS*****************************/
    /// @notice This view returns minimum valid deposit
    /// @return Minimum valid deposit of ETH
    function get_deposit_minimum() external view virtual returns (uint256);

    /// @notice This view returns maximum valid deposit
    /// @return Maximum valid deposit of ETH
    function get_deposit_maximum() external view virtual returns (uint256);

    /// @return current multisig_control_address
    function get_multisig_control_address() external view virtual returns (address);
}

/**
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMWEMMMMMMMMMMMMMMMMMMMMMMMMMM...............MMMMMMMMMMMMM
MMMMMMLOVEMMMMMMMMMMMMMMMMMMMMMM...............MMMMMMMMMMMMM
MMMMMMMMMMHIXELMMMMMMMMMMMM....................MMMMMNNMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMM....................MMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMM88=........................+MMMMMMMMMM
MMMMMMMMMMMMMMMMM....................MMMMM...MMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMM....................MMMMM...MMMMMMMMMMMMMMM
MMMMMMMMMMMM.........................MM+..MMM....+MMMMMMMMMM
MMMMMMMMMNMM...................... ..MM?..MMM.. .+MMMMMMMMMM
MMMMNDDMM+........................+MM........MM..+MMMMMMMMMM
MMMMZ.............................+MM....................MMM
MMMMZ.............................+MM....................MMM
MMMMZ.............................+MM....................DDD
MMMMZ.............................+MM..ZMMMMMMMMMMMMMMMMMMMM
MMMMZ.............................+MM..ZMMMMMMMMMMMMMMMMMMMM
MM..............................MMZ....ZMMMMMMMMMMMMMMMMMMMM
MM............................MM.......ZMMMMMMMMMMMMMMMMMMMM
MM............................MM.......ZMMMMMMMMMMMMMMMMMMMM
MM......................ZMMMMM.......MMMMMMMMMMMMMMMMMMMMMMM
MM............... ......ZMMMMM.... ..MMMMMMMMMMMMMMMMMMMMMMM
MM...............MMMMM88~.........+MM..ZMMMMMMMMMMMMMMMMMMMM
MM.......$DDDDDDD.......$DDDDD..DDNMM..ZMMMMMMMMMMMMMMMMMMMM
MM.......$DDDDDDD.......$DDDDD..DDNMM..ZMMMMMMMMMMMMMMMMMMMM
MM.......ZMMMMMMM.......ZMMMMM..MMMMM..ZMMMMMMMMMMMMMMMMMMMM
MMMMMMMMM+.......MMMMM88NMMMMM..MMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMM+.......MMMMM88NMMMMM..MMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM*/

