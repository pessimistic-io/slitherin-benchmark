// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface IHarvester {
    event RewardTokenConfigUpdated(
        address _tokenAddress,
        uint16 _allowedSlippageBps,
        uint16 _harvestRewardBps,
        address _uniswapV2CompatibleAddr,
        uint256 _liquidationLimit,
        bool _doSwapRewardToken
    );

    // Governable.sol
    function transferGovernance(address _newGovernor) external;

    function claimGovernance() external;

    function governor() external view returns (address);

    // Harvester.sol
    function addSwapToken(address _addr) external;

    function removeSwapToken(address _addr) external;

    function setRewardsProceedsAddress(address _rewardProceedsAddress) external;
    function setLabs(address _labs, uint256 _feeBps) external;
    function setTeam(address _team, uint256 _feeBps) external;
    function getLabs() external view returns (address, uint256);
    function getTeam() external view returns (address, uint256);

    function harvest() external;

    function harvest(address _strategyAddr) external;

    function harvestAndDistribute() external;

    function harvestAndDistribute(address _strategyAddr) external;

    function harvestAndDistribute(address _strategyAddr, address _rewardTo) external;

    function distributeFees() external;

    function distributeProceeds() external;

    function setSupportedStrategy(address _strategyAddress, bool _isSupported)
        external;
}
