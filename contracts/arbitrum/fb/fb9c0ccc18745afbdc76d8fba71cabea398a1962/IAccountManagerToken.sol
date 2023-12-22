pragma solidity 0.8.6;

interface IAccountManagerToken {
    function mint(address to, uint256 id) external;
    function addTokenId(uint256 value) external;
    function tokenId() external returns (uint256);
}
