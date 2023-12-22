pragma solidity ^0.6.10;

interface IGMXRouter {
    function approvePlugin(address _plugin) external ;

    function approvedPlugins(
        address arg1,
        address arg2
    ) external view returns (bool);
}

