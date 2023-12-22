// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IVeToken2 {
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256 _tokenId);
    function increaseAmount(uint256 tokenId, uint256 value) external;
    function increaseUnlockTime(uint256 tokenId, uint256 duration) external;
    function withdraw(uint256 tokenId) external;
    function balanceOfNFT(uint256 _tokenId) external view returns (uint256);
    function controller() external view returns (address);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function balanceOf(address _owner) external view returns (uint256);
    function locked(uint256 tokenId) external view returns (uint256 amount, uint256 endTime);
    function token() external view returns (address);
    function merge(uint _from, uint _to) external;
    function transferFrom(address _from, address _to, uint _tokenId) external;
    function totalSupply() external view returns (uint);
    function voted(uint _tokenId) external view returns (bool);
    function approve(address _approved, uint _tokenId) external;
}
