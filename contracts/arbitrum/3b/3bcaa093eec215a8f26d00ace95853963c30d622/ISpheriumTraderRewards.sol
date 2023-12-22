pragma solidity =0.6.6;

interface ISpheriumTraderRewards {
    function paused() external view returns (bool); 
    function recordTrade(uint[] calldata amounts, address[] calldata path, address _to) external;


}

