// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface PausablePool {
    function setPaused(bool paused) external;
}

contract Pauser {
    bool public executed;
    PausablePool public immutable pool;
    
    constructor(PausablePool _pool) {
        pool = _pool;
    }
    
    function execute() external {
        require(!executed, "Already executed");
        
        pool.setPaused(true);
        executed = true;
    }
}