pragma solidity 0.8.6;

interface IPoolDDL {
    function send(address to, uint amount) external;
    function getTotalBalance() external view returns (uint256 balance);
    function addTotalLocked(uint256 value) external;
    function subTotalLocked(uint256 value) external; 
    function openDeDeLend() external view returns (bool openDeDeLend);
}
