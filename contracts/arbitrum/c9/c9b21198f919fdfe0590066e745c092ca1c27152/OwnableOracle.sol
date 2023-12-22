// SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.19;

import "./Ownable.sol";

abstract contract OwnableOracle is Ownable {
    address public oracle;

    modifier onlyOracle() {
        require(msg.sender == oracle, "Caller is not the oracle");
        _;
    }

    constructor(address _oracle) {
        oracle = _oracle;
    }

    function updateOracle(address _oracle) public onlyOwner {
        oracle = _oracle;
    }
}

