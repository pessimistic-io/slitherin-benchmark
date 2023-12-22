pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import "./SafeMathUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./INVMConfig.sol";

import "./console.sol";

/**
 * @title Common functions
 * @author Nevermined
 */
abstract contract Common {

   /**
    * @notice getCurrentBlockNumber get block number
    * @return the current block number
    */
    function getCurrentBlockNumber()
        external
        view
        returns (uint)
    {
        return block.number;
    }

    /**
     * @dev isContract detect whether the address is 
     *          is a contract address or externally owned account
     * @return true if it is a contract address
     */
    function isContract(address addr)
        public
        view
        returns (bool)
    {
        uint size;
        // solhint-disable-next-line
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    /**
     * @dev Sum the total amount given an uint array
     * @return the total amount
     */
    function calculateTotalAmount(
        uint256[] memory _amounts
    )
    public
    pure
    returns (uint256)
    {
        uint256 _totalAmount;
        for(uint i; i < _amounts.length; i++)
            _totalAmount += _amounts[i];
        return _totalAmount;
    }

    function addressToBytes32(
        address _addr
    ) 
    public 
    pure 
    returns (bytes32) 
    {
        return bytes32(uint256(uint160(_addr)));
    }

    function bytes32ToAddress(
        bytes32 _b32
    ) 
    public 
    pure 
    returns (address) 
    {
        return address(uint160(uint256(_b32)));
    }

    function getNvmConfigAddress() public virtual view returns (address);

    /// Implement IERC2771Recipient
    function getTrustedForwarder() public virtual view returns(address) {
        address addr = getNvmConfigAddress();
        if (addr == address(0)) {
            return address(0);
        }
        return INVMConfig(addr).getTrustedForwarder();
    }

    function hasNVMOperatorRole(address a) public virtual view returns(bool) {
        address addr = getNvmConfigAddress();
        if (addr == address(0)) {
            return false;
        }
        return INVMConfig(addr).hasNVMOperatorRole(a);
    }

    function isTrustedForwarder(address forwarder) public virtual view returns(bool) {
        return forwarder == getTrustedForwarder();
    }

    function _msgSender() internal virtual view returns (address ret) {
        if (msg.data.length >= 20 && isTrustedForwarder(msg.sender)) {
            // At this point we know that the sender is a trusted forwarder,
            // so we trust that the last bytes of msg.data are the verified sender address.
            // extract sender address from the end of msg.data
            // solhint-disable-next-line
            assembly {
                ret := shr(96,calldataload(sub(calldatasize(),20)))
            }
        } else {
            ret = msg.sender;
        }
    }

    function _msgData() internal virtual view returns (bytes calldata ret) {
        if (msg.data.length >= 20 && isTrustedForwarder(msg.sender)) {
            return msg.data[0:msg.data.length-20];
        } else {
            return msg.data;
        }
    }
    
}

abstract contract CommonOwnable is OwnableUpgradeable, Common {
    function _msgSender() internal override(Common,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(Common,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }
}

abstract contract CommonAccessControl is CommonOwnable, AccessControlUpgradeable {
    function _msgSender() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }
}

