// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IORMP {
    function root() external view returns (bytes32);
    function messageCount() external view returns (uint256);
}

contract ORMPWrapper {
    address public immutable ORMP;

    constructor(address ormp) {
        ORMP = ormp;
    }

    function localCommitment() external view returns (uint256 count, bytes32 root) {
        count = IORMP(ORMP).messageCount();
        root = IORMP(ORMP).root();
    }
}

