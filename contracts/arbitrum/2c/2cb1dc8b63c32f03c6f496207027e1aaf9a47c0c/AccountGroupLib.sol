// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC6551AccountLib} from "./ERC6551AccountLib.sol";

library AccountGroupLib {
    struct AccountParams {
        uint32 index;
        uint64 subgroupId;
        address accountGroup;
    }

    function accountParams(address account) internal view returns (AccountParams memory) {
        // assumes salt layout of 0x{accountGroup}{subgroupId}{index}
        bytes32 params = ERC6551AccountLib.salt(account);
        return AccountParams(
            uint32(uint256(params)), uint64(uint256(params) >> 32), address(uint160(uint256(params) >> 96))
        );
        // index = uint32(uint256(params));
        // subgroupId = uint64(uint256(params) >> 32);
        // accountGroup = address(uint160(uint256(params) >> 96));
    }

    function accountParams() internal view returns (AccountParams memory) {
        return accountParams(address(this));
    }
}

