// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;

interface ITournamentV5 {
    function join(uint256) external;
    function create(uint256, uint256, uint256, address, address, uint256, uint256) external;
    function finish(uint256, address[] memory, bool) external;
    function record(uint256, uint256, uint256, uint256) external;
    function update(uint256, uint256, uint256) external;
}
