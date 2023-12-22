// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./WithLimitedSupplyUpgradeable.sol";
import "./Initializable.sol";

/// @dev I (Denim) originally forked this from https://github.com/1001-digital/erc721-extensions/blob/main/contracts/RandomlyAssigned.sol
/// and changed it to use Upgradable Library

/// @author 1001.digital
/// @title Randomly assign tokenIDs from a given set of tokens.
abstract contract RandomlyAssignedUpgradeable is WithLimitedSupplyUpgradeable {
    // Used for random index assignment
    mapping(uint256 => uint256) private tokenMatrix;

    // The initial token ID
    uint256 private startFrom;

    function initialize(
        uint256 totalSupply_,
        uint256 startFrom_
    ) internal initializer {
        WithLimitedSupplyUpgradeable.__WithLimitedSupplyUpgradeable_init(
            totalSupply_
        );
        startFrom = startFrom_;
    }

    /// Get the next token ID
    /// @dev Randomly gets a new token ID and keeps track of the ones that are still available.
    /// @return the next token ID
    function nextToken()
        internal
        override
        ensureAvailability
        returns (uint256)
    {
        uint256 maxIndex = totalSupply() - tokenCount();
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    msg.sender,
                    block.coinbase,
                    block.difficulty,
                    block.gaslimit,
                    block.timestamp
                )
            )
        ) % maxIndex;

        uint256 value = 0;
        if (tokenMatrix[random] == 0) {
            // If this matrix position is empty, set the value to the generated random number.
            value = random;
        } else {
            // Otherwise, use the previously stored number from the matrix.
            value = tokenMatrix[random];
        }

        // If the last available tokenID is still unused...
        if (tokenMatrix[maxIndex - 1] == 0) {
            // ...store that ID in the current matrix position.
            tokenMatrix[random] = maxIndex - 1;
        } else {
            // ...otherwise copy over the stored number to the current matrix position.
            tokenMatrix[random] = tokenMatrix[maxIndex - 1];
        }

        // Increment counts
        super.nextToken();

        return value + startFrom;
    }
}

