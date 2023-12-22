// SPDX-License-Identifier: MIT
// Mateline Contracts (RandomPoolLib.sol)

pragma solidity ^0.8.0;

import "./Random.sol";

/**
 * @dev Random pool that allow user random in different rate section
 */
library RandomPoolLib {

    // random set with rate and range
    struct RandomSet {
        uint32 rate;
        uint rangMin;
        uint rangMax;
    }

    // random pool with an array of random set
    struct RandomPool {
        uint32 totalRate;
        RandomSet[] pool;
    }

    // initialize a random pool
    function initRandomPool(RandomPool storage pool) external {
        for(uint i=0; i< pool.pool.length; ++i){
            pool.totalRate += pool.pool[i].rate;
        }

        require(pool.totalRate > 0);
    }

    // use and randomNum to fetch a random result in the random set array
    function random(RandomPool storage pool, uint256 r) external view returns(uint ret) {
        require(pool.totalRate > 0);

        uint32 rate = uint32((r>>224) % pool.totalRate);
        uint32 curRate = 0;
        for(uint i=0; i<pool.pool.length; ++i){
            curRate += pool.pool[i].rate;
            if(rate > curRate){
                continue;
            }

            return randBetween(pool.pool[i].rangMin, pool.pool[i].rangMax, r);
        }
    }

    // input r and min,max, return a number between [min, max] with r
    function randBetween(
        uint256 min,
        uint256 max,
        uint256 r
    ) public pure returns (uint256 ret) {
        if(min >= max) {
            return min;
        }

        uint256 rang = (max+1) - min;
        return uint256(min + (r % rang));
    }
}
