// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

abstract contract AntiFlashload {
    // Info of each user that stakes block no.
    mapping(uint256 => mapping(address => uint256)) public _blockMap;
    uint256 public flashloadBlk; // at least 1 block.

    constructor() {
        __Flashload_init(1);
    }

    function __Flashload_init(uint256 _initBlk) internal {
        flashloadBlk = _initBlk;
    }

    modifier enterFlashload(uint256 id) {
        _blockMap[id][msg.sender] = block.number;
        _;
    }

    modifier leaveFlashload(uint256 id) {
        require(
            block.number >= _blockMap[id][msg.sender] + flashloadBlk,
            "!anti flashload"
        );
        _;
    }
}

