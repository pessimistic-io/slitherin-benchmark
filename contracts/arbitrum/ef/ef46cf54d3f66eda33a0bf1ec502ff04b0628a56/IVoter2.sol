// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IVoter2 {
    function vote(uint256 tokenId, address[] calldata poolVote, int256[] calldata weights) external;
    function whitelist(address token, uint256 tokenId) external;
    function reset(uint256 tokenId) external;
    function gauges(address lp) external view returns (address);
    function ve() external view returns (address);
    function minter() external view returns (address);
    function bribes(address gauge) external view returns (address);
    function votes(uint256 id, address lp) external view returns (uint256);
    function poolVote(uint256 id, uint256 index) external view returns (address);
    function lastVote(uint256 id) external view returns (uint256);
    function weights(address pool) external view returns (int256);
    function factory() external view returns (address);
}
