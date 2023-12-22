// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IAddressProvider {
    
    function networkToken() external view returns (address);
    function usdc() external view returns (address);
    function usdt() external view returns (address);
    function dai() external view returns (address);
    function swapper() external view returns (address);
    function reserve() external view returns (address);
    function lendVault() external view returns (address);
    function borrowerManager() external view returns (address);
    function oracle() external view returns (address);
    function uniswapV3Integration() external view returns (address);
    function uniswapV3StrategyData() external view returns (address);
    function uniswapV3StrategyMigrator() external view returns (address);
    function uniswapV3StrategyLogic() external view returns (address);
    function borrowerBalanceCalculator() external view returns (address);
    function keeper() external view returns (address);
    function governance() external view returns (address);
    function guardian() external view returns (address);
    function controller() external view returns (address);
    function vaults(uint index) external view returns (address);
    function getVaults() external view returns (address[] memory);
    function rewardDistribution() external view returns (address);
    function rewardToken() external view returns (address);

    function setNetworkToken(address token) external;
    function setUsdc(address token) external;
    function setUsdt(address token) external;
    function setDai(address token) external;
    function setReserve(address _reserve) external;
    function setSwapper(address _swapper) external;
    function setLendVault(address _lendVault) external;
    function setBorrowerManager(address _manager) external;
    function setOracle(address _oracle) external;
    function setUniswapV3Integration(address _integration) external;
    function setUniswapV3StrategyData(address _address) external;
    function setUniswapV3StrategyLogic(address _logic) external;
    function setUniswapV3StrategyMigrator(address _migrator) external;
    function setKeeper(address _keeper) external;
    function setGovernance(address _governance) external;
    function setGuardian(address _guardian) external;
    function setController(address _controller) external;
    function addVault(address _vault) external;
    function removeVault(address _vault) external;
}
