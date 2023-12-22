// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface IPYESwapToken {

    event Burn(address burner, uint256 amount);

	event BridgeInitiated(address indexed user, uint256 amount, uint256 fromChain, uint256 toChain);
    
    event BridgeCompleted(address indexed user, uint256 amount, uint256 fromChain, uint256 toChain);
    
    event BridgeCanceled(address indexed user, uint256 amount, uint256 fromChain, uint256 toChain);
    
    event CrossChainExecutorSet(address indexed executor);
    
    event RewardsMinted(address indexed to, uint256 amount);

    event VestedTokensMinted(address indexed vestingContract, address indexed to, uint256 amount);
    
    event ContractUnpaused(uint256 timeStamp);
    
    event CrossChainEnabled(uint256 timeStamp);
    
    event SingleChainEnabled(uint256 enabledChainId, uint256 gasForBridge, uint256 timeStamp);
    
    event SingleChainDisabled(uint256 disabledChainId, uint256 timeStamp);
    
    event CrossChainDisabled(uint256 timeStamp);
    
    event TokenRescued(address indexed token, uint256 amount);

    event StakingContractSet(address newRewardsContract);

    event RewardMinterAdded(address minter);

    event RewardMinterRemoved(address minter);

    event TokenBurnerAdded(address burner);

    event TokenBurnerRemoved(address burner);

    function setAllowedWhilePaused(address account, bool flag) external;
    
    function unPauseContract(address staking) external;

    function addStakingContract(address _staking) external;

    function addRewardMinter(address _minter) external;

    function removeRewardMinter(address _minter) external;

    function addTokenBurner(address _burner) external;

    function removeTokenBurner(address _burner) external;

    function setCrossChainExecutor(address _executor, bool revoke) external;

    function enableCrossChain(uint256[] calldata _chainIds, uint256[] calldata _gas) external;

    function enableSingleChain(uint256 _chainId, uint256 _gas) external;

    function disableSingleChain(uint256 _chainId) external;

    function pauseCrossChain() external;

    function bridgeFrom(uint256 amount, uint256 toChain) external payable;

    function bridgeTo(address account, uint256 amount, uint256 fromChain) external;

    function cancelBridge(address account, uint256 amount, uint256 toChain) external;

    function mint(address to, uint256 amount) external;

    function mintVestedTokens(uint256 amount, address to) external;

    function rescueERC20(address token, uint256 amount) external;

    function transferReward(address to, uint256 amount) external returns (bool);

    function setIsSnapshotter(address account, bool flag) external;

    function snapshot() external;

    function burn(uint256 amount) external;

    function getEnabledChains() external view returns (uint256[] memory);

    function staked(address) external view returns (uint256);

    function isStakingContract(address) external view returns (bool);

    function getOwnedBalance(address account) external view returns (uint256);

    function getCurrentSnapshotId() external view returns (uint256);

}
