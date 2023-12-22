// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGen0 {
    function isStaked(uint256 tokenId) external view returns (bool);
    function stakeNft(uint256 tokenId) external;
    function unstakeNft(uint256 tokenId) external;

    event Staked(uint256 indexed tokenId);
    event Unstaked(uint256 indexed tokenId);

    event AllowUnstakingChanged(bool allow);
    event AllowStakingChanged(bool allow);
    event BaseUriChanged(string baseUri);
}
