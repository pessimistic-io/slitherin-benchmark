// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

library BuyMany {
    bytes32 private constant buyManyType =
        keccak256("Info(address to,uint256 amount,uint256[] tokenIds)");

    struct Many {
        address to;
        uint256 amount;
        uint256[] tokenIds;
    }

    function buyHash(Many calldata info) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    buyManyType,
                    info.to,
                    info.amount,
                    keccak256(abi.encodePacked(info.tokenIds))
                )
            );
    }
}

