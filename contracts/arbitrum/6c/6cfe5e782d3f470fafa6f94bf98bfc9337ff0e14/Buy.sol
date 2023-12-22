// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

library Buy {
    bytes32 private constant buyType =
        keccak256(
            "Info(address to,uint256 amount,uint256 tokenId)"
        );
    struct Info {
        address to;
        uint256 amount;
        uint256 tokenId;
    }

    function dropHash(Info memory info) internal pure returns (bytes32) {
        return
            keccak256(abi.encode(buyType, info.to, info.amount, info.tokenId));
    }
}

