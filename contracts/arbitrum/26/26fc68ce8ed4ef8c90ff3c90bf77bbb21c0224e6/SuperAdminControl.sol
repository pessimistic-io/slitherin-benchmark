// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./Ownable.sol";

/// @author YLDR <admin@apyflow.com>
contract SuperAdminControl is Ownable {
    error LowLevelCallFailed();

    struct CallData {
        address to;
        bytes data;
        uint256 value;
    }

    function call(CallData[] calldata calls) external onlyOwner {
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success,) = calls[i].to.call{value: calls[i].value}(calls[i].data);
            if (!success) {
                revert LowLevelCallFailed();
            }
        }
    }
}

