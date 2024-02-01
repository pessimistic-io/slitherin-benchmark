//SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "./IETH_Bridge_Logic.sol";
import "./IMultisigControl.sol";
import "./ETH_Asset_Pool.sol";

/// @title ETH Bridge Logic
/// @author Vega Protocol
/// @notice This contract is used by Vega network users to deposit and withdraw ETH to/from Vega.
// @notice All funds deposited/withdrawn are to/from the assigned ETH_Asset_Pool
contract ETH_Bridge_Logic is IETH_Bridge_Logic {
    address payable ETH_asset_pool_address;

    // minimum deposit amt
    uint256 minimum_deposit;
    // maximum deposit amt
    uint256 maximum_deposit;

    /// @param ETH_asset_pool Initial Asset Pool contract address
    constructor(address payable ETH_asset_pool) {
        require(ETH_asset_pool != address(0), "invalid asset pool address");
        ETH_asset_pool_address = ETH_asset_pool;
    }

    function multisig_control_address() internal view returns (address) {
        return ETH_Asset_Pool(ETH_asset_pool_address).multisig_control_address();
    }

    /// @notice This function sets the minimum allowable deposit for ETH
    /// @param minimum_amount Minimum deposit amount
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @notice See MultisigControl for more about signatures
    /// @dev Emits ETH_Deposit_Minimum_Set if successful
    function set_deposit_minimum(
        uint256 minimum_amount,
        uint256 nonce,
        bytes memory signatures
    ) external override {
        bytes memory message = abi.encode(minimum_amount, nonce, "set_deposit_minimum");
        require(
            IMultisigControl(multisig_control_address()).verify_signatures(signatures, message, nonce),
            "bad signatures"
        );
        minimum_deposit = minimum_amount;
        emit ETH_Deposit_Minimum_Set(minimum_amount, nonce);
    }

    /// @notice This function sets the maximum allowable deposit for ETH
    /// @param maximum_amount Maximum deposit amount
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @notice See MultisigControl for more about signatures
    /// @dev Emits ETH_Deposit_Maximum_Set if successful
    function set_deposit_maximum(
        uint256 maximum_amount,
        uint256 nonce,
        bytes memory signatures
    ) external override {
        bytes memory message = abi.encode(maximum_amount, nonce, "set_deposit_maximum");
        require(
            IMultisigControl(multisig_control_address()).verify_signatures(signatures, message, nonce),
            "bad signatures"
        );
        maximum_deposit = maximum_amount;
        emit ETH_Deposit_Maximum_Set(maximum_amount, nonce);
    }

    /// @notice This function allows the withdrawal of ETH
    /// @param amount Amount of ETH to withdraw
    /// @param expiry Vega-assigned timestamp of withdrawal order expiration
    /// @param target Target Ethereum address to receive withdrawn ETH
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed order
    /// @notice See MultisigControl for more about signatures
    /// @dev Emits ETH_Withdrawn if successful
    function withdraw_asset(
        uint256 amount,
        uint256 expiry,
        address payable target,
        uint256 nonce,
        bytes memory signatures
    ) external override {
        require(expiry > block.timestamp, "withdrawal has expired");
        bytes memory message = abi.encode(amount, expiry, target, nonce, "withdraw_asset");
        require(
            IMultisigControl(multisig_control_address()).verify_signatures(signatures, message, nonce),
            "bad signatures"
        );
        ETH_Asset_Pool(ETH_asset_pool_address).withdraw(target, amount);
        emit ETH_Withdrawn(target, amount, nonce);
    }

    /// @notice This function allows a user to deposit ETH into Vega
    /// @param vega_public_key Target vega public key to be credited with this deposit
    /// @dev Emits ETH_Deposited if successful
    function deposit_asset(bytes32 vega_public_key) external payable override {
        require(maximum_deposit == 0 || msg.value <= maximum_deposit, "deposit above maximum");
        require(msg.value >= minimum_deposit, "deposit below minimum");
        ETH_asset_pool_address.transfer(msg.value);
        emit ETH_Deposited(msg.sender, msg.value, vega_public_key);
    }

    /***************************VIEWS*****************************/
    /// @notice This view returns minimum valid deposit
    /// @return Minimum valid deposit of ETH
    function get_deposit_minimum() external view override returns (uint256) {
        return minimum_deposit;
    }

    /// @notice This view returns maximum valid deposit
    /// @return Maximum valid deposit of ETH
    function get_deposit_maximum() external view override returns (uint256) {
        return maximum_deposit;
    }

    /// @return current multisig_control_address
    function get_multisig_control_address() external view override returns (address) {
        return multisig_control_address();
    }
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

