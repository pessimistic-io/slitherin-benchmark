pragma solidity 0.6.12;

interface IChronosGauge {
    function bribe() external view returns (address);
    function balanceOf(address) external view returns (uint256);
    function isReward(address) external view returns (bool);
    function getReward(address account, address[] memory tokens) external;
    function getAllReward() external;
    function earned(address token, address account) external view returns (uint);
    function stake() external view returns (address);
    function deposit(uint amount, uint tokenId) external;
    function depositAll() external;
    function withdraw(uint amount) external;
    function withdrawAndHarvestAll() external;
    function withdrawToken(uint amount, uint tokenId) external;
    function tokenIds(address owner) external view returns (uint256 tokenId);
}
