//SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "./IMultisigControl.sol";

/// @title ETH Asset Pool
/// @author Vega Protocol
/// @notice This contract is the target for all deposits to the ETH Bridge via ETH_Bridge_Logic
contract ETH_Asset_Pool {
    event Multisig_Control_Set(address indexed new_address);
    event Bridge_Address_Set(address indexed new_address);
    event Received(address indexed sender, uint256 amount);

    /// @return Current MultisigControl contract address
    address public multisig_control_address;

    /// @return Current ETH_Bridge_Logic contract address
    address public ETH_bridge_address;

    /// @param multisig_control The initial MultisigControl contract address
    /// @notice Emits Multisig_Control_Set event
    constructor(address multisig_control) {
        require(multisig_control != address(0), "invalid MultisigControl address");
        multisig_control_address = multisig_control;
        emit Multisig_Control_Set(multisig_control);
    }

    /// @param new_address The new MultisigControl contract address.
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed set_multisig_control order
    /// @notice See MultisigControl for more about signatures
    /// @notice Emits Multisig_Control_Set event
    function set_multisig_control(
        address new_address,
        uint256 nonce,
        bytes memory signatures
    ) external {
        require(new_address != address(0), "invalid MultisigControl address");
        uint256 size;
        assembly {
            size := extcodesize(new_address)
        }
        require(size > 0, "new address must be contract");
        bytes memory message = abi.encode(new_address, nonce, "set_multisig_control");
        require(
            IMultisigControl(multisig_control_address).verify_signatures(signatures, message, nonce),
            "bad signatures"
        );
        multisig_control_address = new_address;
        emit Multisig_Control_Set(new_address);
    }

    /// @param new_address The new ETH_Bridge_Logic contract address.
    /// @param nonce Vega-assigned single-use number that provides replay attack protection
    /// @param signatures Vega-supplied signature bundle of a validator-signed set_bridge_address order
    /// @notice See MultisigControl for more about signatures
    /// @notice Emits Bridge_Address_Set event
    function set_bridge_address(
        address new_address,
        uint256 nonce,
        bytes memory signatures
    ) external {
        require(new_address != address(0), "invalid bridge address");
        bytes memory message = abi.encode(new_address, nonce, "set_bridge_address");
        require(
            IMultisigControl(multisig_control_address).verify_signatures(signatures, message, nonce),
            "bad signatures"
        );
        ETH_bridge_address = new_address;
        emit Bridge_Address_Set(new_address);
    }

    /// @notice This function can only be run by the current "multisig_control_address" and, if available, will send the target eth to the target
    /// @param target Target Ethereum address that the ETH will be sent to
    /// @param amount Amount of ETH to withdraw
    /// @dev amount is in wei, 1 wei == 0.000000000000000001 ETH
    function withdraw(address payable target, uint256 amount) external {
        require(target != address(0), "invalid target address");
        require(msg.sender == ETH_bridge_address, "msg.sender not authorized bridge");
        /// @dev reentry is protected by the non-reusable nonce in the signature check in the ETH_Bridge_Logic
        (bool success, ) = target.call{value: amount}("");
        require(success, "eth transfer failed");
    }

    /// @notice A contract can have at most one receive function,
    /// declared using receive() external payable { ... }
    /// (without the function keyword). This function cannot have arguments,
    /// cannot return anything and must have external visibility and payable state
    /// mutability. It is executed on a call to the contract with empty calldata.
    /// This is the function that is executed on plain Ether transfers (e.g. via .send()
    /// or .transfer()). If no such function exists, but a payable fallback
    /// function exists, the fallback function will be called on a plain Ether
    /// transfer. If neither a receive Ether nor a payable fallback function is
    /// present, the contract cannot receive Ether through regular transactions
    /// and throws an exception.
    receive() external payable {
        emit Received(msg.sender, msg.value);
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

