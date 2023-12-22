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
        string memory poolName,
        uint256 poolMaxCap,
        uint256 saleStartTime,
        uint256 saleEndTime,
        uint256 noOfTiers,
        uint256 totalParticipants,
        address payable projectOwner,
        address fundTokenAddress
    ) public onlyOwner returns (address) {
        Arbipad pool;

        pool = new Arbipad(
            owner(),
            poolName,
            poolMaxCap,
            saleStartTime,
            saleEndTime,
            noOfTiers,
            totalParticipants,
            projectOwner,
            fundTokenAddress
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

        return address(pool);
    }
}

