pragma solidity 0.6.12;

interface IGauge {
    function bribe() external view returns (address);
    function balanceOf(address) external view returns (uint256);
    function isReward(address) external view returns (bool);
    function getReward(address account, address[] memory tokens) external;
    function earned(address token, address account) external view returns (uint);
    function stake() external view returns (address);
    function deposit(uint amount, uint tokenId) external;
    function depositAll(uint tokenId) external;
    function withdraw(uint amount) external;
    function withdrawAll() external;
    function withdrawToken(uint amount, uint tokenId) external;
    function tokenIds(address owner) external view returns (uint256 tokenId);
}
