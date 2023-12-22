//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

library Random {
    function numberChosen(
        uint256 min,
        uint256 max,
        uint256 nonce
    ) internal view returns (uint256) {
        uint256 amount = uint(
            keccak256(
                abi.encodePacked(block.timestamp + nonce, msg.sender, block.number)
            )
        ) % (max - min);
        amount = amount + min;
        return amount;
    }
}

