// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface ISingleVault {

    event VaultInitialized(address _by, string _name, string _symbol, address _asset);
    event CapitalPaused();
    event CapitalUnpaused();
    event Deposit(address, uint256, uint256);
    event Withdraw(address, uint256, uint256);
    event QuickDeposited(address, address, uint256);
    event StrategyApproved(address _addr);
    event StrategyRemoved(address _addr);


    // ERC20.sol
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    // SVaultCore.sol
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _shares) external;
    function balance() external view returns (uint256);
    function available() external view returns (uint256);
    function claimReward(address _strategy) external returns (uint256);


    // SVaultStorage.sol
    struct StrategyWithWeight {
        address strategy;
        uint256 minWeight;
        uint256 targetWeight;
        uint256 maxWeight;
        bool enabled;
        bool enabledReward;
    }
    struct CXVault {
        address xvault;
        uint8 chainId;
        uint256 allocation;
    }
    function capitalPaused() external view returns (bool);
    function asset() external view returns (address);

    // SVaultAdmin.sol
    function approveStrategy(address _addr) external;
    function removeStrategy(address _addr) external;
    function pauseCapital() external;
    function unpauseCapital() external;
    function withdrawAllFromStrategy(address _strategyAddr) external;
    function withdrawAllFromStrategies() external;
    function setStrategyWithWeights(StrategyWithWeight[] calldata _strategyWithWeights) external;
    function setBridge(address _bridge) external;
    function setIsParent(bool _isParent) external;
    function setCXVaults(CXVault[] calldata _childXVaults) external;
    function setQuickDepositStrategies(address[] calldata _quickDepositStrategies) external;
    function getQuickDepositStrategies() external view returns (address[] memory);
    function setSwapper(address _swapper) external;
    function setWithdrawLockup(uint256 _duration) external;
    function setNextPayoutTime(uint256 _nextPayoutTime) external;
    function setPayoutIntervals(uint256 _payoutPeriod, uint256 _payoutTimeRange) external;
    function payout() external;
    function rebalance() external;
}
