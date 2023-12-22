// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IController {
    function vaults(address) external view returns (address);

    function setVault(address _token, address _vault) external;
    function withdrawAll(address _token) external;
    function inCaseTokensGetStuck(address _token, uint256 _amount) external;
    function inCaseStrategyTokenGetStuck(address _strategy, address _token) external;
    function forceWithdraw(address _token, uint256 _amount) external;
    function harvest(address _token) external;
    function earn(address _token) external;
    function migrateStrategy(address _oldAddress, address _newAddress) external;
    function resetStrategyPnl(address _strategy) external;
    function withdraw(address _token, uint256 _amount) external;
}

