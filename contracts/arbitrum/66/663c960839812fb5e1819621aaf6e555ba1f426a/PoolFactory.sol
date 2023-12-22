//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Arbipad.sol";

/**
 * @dev Contract module to deploy a pool automatically
 */
contract PoolFactory is Ownable {
    /**
     * @dev Emitted when launhPool function is succesfully called and a pool is created
     */
    event PoolCreation(
        uint256 indexed timestamp,
        Arbipad indexed poolAddress,
        address indexed projectOwner,
        uint256 poolMaxCap,
        uint256 saleStartTime,
        uint256 saleEndTime,
        uint256 noOfTiers,
        uint256 totalParticipants
    );

    /**
     * @dev Create a pool.
     *
     * emits a {PoolCreation} event
     */
    function launchPool(
        string memory name,
        uint256 poolMaxCap,
        uint256 saleStartTime,
        uint256 saleEndTime,
        uint256 noOfTiers,
        uint256 totalParticipants,
        address payable projectOwner,
        address tokenAddress
    ) public onlyOwner {
        Arbipad pool;

        pool = new Arbipad(
            owner(),
            name,
            poolMaxCap,
            saleStartTime,
            saleEndTime,
            noOfTiers,
            totalParticipants,
            projectOwner,
            tokenAddress
        );

        emit PoolCreation(
            block.timestamp,
            pool,
            projectOwner,
            poolMaxCap,
            saleStartTime,
            saleEndTime,
            noOfTiers,
            totalParticipants
        );
    }
}

