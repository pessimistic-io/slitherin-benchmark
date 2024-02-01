//SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

/// @title ERC20 Bridge Logic Interface
/// @author Vega Protocol
/// @notice Implementations of this interface are used by Vega network users to deposit and withdraw ERC20 tokens to/from Vega.
// @notice All funds deposited/withdrawn are to/from the ERC20_Asset_Pool
abstract contract IERC20_Bridge_Logic_Restricted {
    /***************************EVENTS****************************/
    event Asset_Withdrawn(address indexed user_address, address indexed asset_source, uint256 amount, uint256 nonce);
    event Asset_Deposited(
        address indexed user_address,
        address indexed asset_source,
        uint256 amount,
        bytes32 vega_public_key
    );
    event Asset_Listed(address indexed asset_source, bytes32 indexed vega_asset_id, uint256 nonce);
    event Asset_Removed(address indexed asset_source, uint256 nonce);
    event Asset_Limits_Updated(address indexed asset_source, uint256 lifetime_limit, uint256 withdraw_threshold);
    event Bridge_Withdraw_Delay_Set(uint256 withdraw_delay);
    event Bridge_Stopped();
    event Bridge_Resumed();
    event Depositor_Exempted(address indexed depositor);
    event Depositor_Exemption_Revoked(address indexed depositor);

    /***************************FUNCTIONS*************************/
    /// @notice This function lists the given ERC20 token contract as valid for deposit to this bridge
    /// @param asset_source Contract address for given ERC20 token
    /// @param vega_asset_id Vega-generated asset ID for internal use in Vega Core
    /// @param lifetime_limit Initial lifetime deposit limit *RESTRICTION FEATURE*
    /// @param withdraw_threshold Amount at which the withdraw delay goes into effect *RESTRICTION FEATURE*
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @notice See MultisigControl for more about signatures
    /// @dev MUST emit Asset_Listed if successful
    function list_asset(
        address asset_source,
        bytes32 vega_asset_id,
        uint256 lifetime_limit,
        uint256 withdraw_threshold,
        uint256 nonce,
        bytes memory signatures
    ) external virtual;

    /// @notice This function removes from listing the given ERC20 token contract. This marks the token as invalid for deposit to this bridge
    /// @param asset_source Contract address for given ERC20 token
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @notice See MultisigControl for more about signatures
    /// @dev MUST emit Asset_Removed if successful
    function remove_asset(
        address asset_source,
        uint256 nonce,
        bytes memory signatures
    ) external virtual;

    /// @notice This function sets the lifetime maximum deposit for a given asset
    /// @param asset_source Contract address for given ERC20 token
    /// @param lifetime_limit Deposit limit for a given ethereum address
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @dev asset must first be listed
    function set_asset_limits(
        address asset_source,
        uint256 lifetime_limit,
        uint256 threshold,
        uint256 nonce,
        bytes calldata signatures
    ) external virtual;

    /// @notice This function sets the withdraw delay for withdrawals over the per-asset set thresholds
    /// @param delay Amount of time to delay a withdrawal
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    function set_withdraw_delay(
        uint256 delay,
        uint256 nonce,
        bytes calldata signatures
    ) external virtual;

    /// @notice This function triggers the global bridge stop that halts all withdrawals and deposits until it is resumed
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @dev bridge must not be stopped already
    /// @dev MUST emit Bridge_Stopped if successful
    function global_stop(uint256 nonce, bytes calldata signatures) external virtual;

    /// @notice This function resumes bridge operations from the stopped state
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @dev bridge must be stopped
    /// @dev MUST emit Bridge_Resumed if successful
    function global_resume(uint256 nonce, bytes calldata signatures) external virtual;

    /// @notice this function allows the exemption_lister to exempt a depositor from the deposit limits
    /// @notice this feature is specifically for liquidity and rewards providers
    /// @dev MUST emit Depositor_Exempted if successful
    function exempt_depositor() external virtual;

    /// @notice this function allows the exemption_lister to revoke a depositor's exemption from deposit limits
    /// @notice this feature is specifically for liquidity and rewards providers
    /// @dev MUST emit Depositor_Exemption_Revoked if successful
    function revoke_exempt_depositor() external virtual;

    /// @notice This function withdrawals assets to the target Ethereum address
    /// @param asset_source Contract address for given ERC20 token
    /// @param amount Amount of ERC20 tokens to withdraw
    /// @param target Target Ethereum address to receive withdrawn ERC20 tokens
    /// @param creation Timestamp of when requestion was created *RESTRICTION FEATURE*
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @notice See MultisigControl for more about signatures
    /// @dev MUST emit Asset_Withdrawn if successful
    function withdraw_asset(
        address asset_source,
        uint256 amount,
        address target,
        uint256 creation,
        uint256 nonce,
        bytes memory signatures
    ) external virtual;

    /// @notice this view returns true if the given despoitor address has been exempted from deposit limits
    /// @param depositor The depositor to check
    /// @return true if depositor is exempt
    function is_exempt_depositor(address depositor) external view virtual returns (bool);

    /// @notice This function allows a user to deposit given ERC20 tokens into Vega
    /// @param asset_source Contract address for given ERC20 token
    /// @param amount Amount of tokens to be deposited into Vega
    /// @param vega_public_key Target Vega public key to be credited with this deposit
    /// @dev MUST emit Asset_Deposited if successful
    /// @dev ERC20 approve function should be run before running this
    /// @notice ERC20 approve function should be run before running this
    function deposit_asset(
        address asset_source,
        uint256 amount,
        bytes32 vega_public_key
    ) external virtual;

    /***************************VIEWS*****************************/
    /// @notice This view returns true if the given ERC20 token contract has been listed valid for deposit
    /// @param asset_source Contract address for given ERC20 token
    /// @return True if asset is listed
    function is_asset_listed(address asset_source) external view virtual returns (bool);

    /// @notice This view returns the lifetime deposit limit for the given asset
    /// @param asset_source Contract address for given ERC20 token
    /// @return Lifetime limit for the given asset
    function get_asset_deposit_lifetime_limit(address asset_source) external view virtual returns (uint256);

    /// @notice This view returns the given token's withdraw threshold above which the withdraw delay goes into effect
    /// @param asset_source Contract address for given ERC20 token
    /// @return Withdraw threshold
    function get_withdraw_threshold(address asset_source) external view virtual returns (uint256);

    /// @return current multisig_control_address
    function get_multisig_control_address() external view virtual returns (address);

    /// @param asset_source Contract address for given ERC20 token
    /// @return The assigned Vega Asset ID for given ERC20 token
    function get_vega_asset_id(address asset_source) external view virtual returns (bytes32);

    /// @param vega_asset_id Vega-assigned asset ID for which you want the ERC20 token address
    /// @return The ERC20 token contract address for a given Vega Asset ID
    function get_asset_source(bytes32 vega_asset_id) external view virtual returns (address);
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

