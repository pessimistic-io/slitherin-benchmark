pragma solidity 0.6.12;

interface IGHALend {
    function getReward() external;
    function deposit(uint amount) external;
    function withdraw(uint amount) external;
    function xdeposits(address _user) external view returns (uint256);
    function pendingTokenPerxDeposit() external view returns (uint256);
}
