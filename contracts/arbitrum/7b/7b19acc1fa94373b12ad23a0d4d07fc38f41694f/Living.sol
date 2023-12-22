// SPDX-License-Identifier: ISC

pragma solidity ^0.8.0;

abstract contract Living {
    uint256 alive;

    modifier live {
        require(alive != 0, "Living/not-live");
        _;
    }

    function stop() external {
        alive = 0;
    }

    function run() public {
        alive = 1;
    }
}
