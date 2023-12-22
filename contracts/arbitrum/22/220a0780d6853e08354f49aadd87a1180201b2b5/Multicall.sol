// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ERC20} from "./ERC20.sol";

abstract contract Multicall {
    error CallError(uint256 index, bytes errorData);

    /// @notice Call multiple methods in a single transaction
    /// @param data Array of encoded function calls
    /// @return results Array of returned data
    function multicall(bytes[] calldata data) public payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            bool success;
            (success, results[i]) = address(this).delegatecall(data[i]);
            if (!success) revert CallError(i, results[i]);
        }
    }

    // ----- common utils to use in multicall -----

    /// @notice Permit any ERC20 token
    function permitERC20(
        address token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable {
        ERC20(token).permit(owner, spender, value, deadline, v, r, s);
    }

    /// @notice Permit DAI
    function permitDAI(
        address dai, //
        address owner,
        address spender,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable {
        IDAIPermit(dai).permit(owner, spender, ERC20(dai).nonces(owner), deadline, true, v, r, s);
    }

    /// @notice Get value of a storage slot
    function getStorageSlot(bytes32 slot) public view returns (bytes32 value) {
        assembly ("memory-safe") {
            value := sload(slot)
        }
    }
}

interface IDAIPermit {
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

