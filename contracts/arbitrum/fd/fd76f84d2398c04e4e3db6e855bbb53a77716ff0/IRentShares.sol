// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

interface IRentShares {
    // mapping(uint256 => uint256) public totalRentSharePoints;
    function totalRentSharePoints(uint256 _nftId) external view returns(uint256);
    

    function getRentShares(address _addr, uint256 _nftId) external view returns(uint256);
    function getAllRentOwed(address _addr, uint256 _mod) external view returns (uint256);
    function getRentOwed(address _addr, uint256 _nftId) external view returns (uint256);
    function canClaim(address _addr, uint256 _mod) external view returns (uint256);
    function collectRent(uint256 _nftId, uint256 _amount) external;
    function claimRent(address _address, uint256 _mod) external;
    function addPendingRewards(address _addr, uint256 _amount) external;
    function giveShare(address _addr, uint256 _nftId) external;
    function removeShare(address _addr, uint256 _nftId) external;
    function batchGiveShares(address _addr, uint256[] calldata _nftIds) external;
    function batchRemoveShares(address _addr, uint256[] calldata _nftIds) external;
}
