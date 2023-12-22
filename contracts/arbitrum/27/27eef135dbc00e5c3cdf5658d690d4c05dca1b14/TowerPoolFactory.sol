// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./TowerPool.sol";

contract TowerPoolFactory is Ownable {
    mapping(address => address) public towerPools; // token => TowerPool
    mapping(address => address) public tokenForTowerPool; // TowerPool => token
    mapping(address => bool) public isTowerPool;
    address[] public allTowerPools;

    event TowerPoolCreated(
        address indexed towerPool,
        address creator,
        address indexed token
    );
    event Deposit(
        address indexed token,
        address indexed towerPool,
        uint256 amount
    );
    event Withdraw(
        address indexed token,
        address indexed towerPool,
        uint256 amount
    );
    event NotifyReward(
        address indexed sender,
        address indexed reward,
        uint256 amount
    );
    
    function emitDeposit(
        address account,
        uint256 amount
    ) external {
        require(isTowerPool[msg.sender]);
        emit Deposit(account, msg.sender, amount);
    }

    function emitWithdraw(
        address account,
        uint256 amount
    ) external {
        require(isTowerPool[msg.sender]);
        emit Withdraw(account, msg.sender, amount);
    }

    function allTowerPoolsLength() external view returns (uint256) {
        return allTowerPools.length;
    }

    function createTowerPool(address _stake, address[] memory _allowedRewardTokens)
        external
        onlyOwner
        returns (address towerPool)
    {
        require(
            towerPools[_stake] == address(0),
            "TowerPoolFactory: POOL_EXISTS"
        );
        bytes memory bytecode = type(TowerPool).creationCode;
        assembly {
            towerPool := create2(0, add(bytecode, 32), mload(bytecode), _stake)
        }
        TowerPool(towerPool)._initialize(
            _stake,
            _allowedRewardTokens
        );
        towerPools[_stake] = towerPool;
        tokenForTowerPool[towerPool] = _stake;
        isTowerPool[towerPool] = true;
        allTowerPools.push(towerPool);
        emit TowerPoolCreated(towerPool, msg.sender, _stake);
    }

    function claimRewards(
        address[] memory _towerPools,
        address[][] memory _tokens
    ) external {
        for (uint256 i = 0; i < _towerPools.length; i++) {
            TowerPool(_towerPools[i]).getReward(msg.sender, _tokens[i]);
        }
    }
    
    function whitelistTowerPoolRewards(
        address[] calldata _towerPools,
        address[] calldata _rewards
    ) external onlyOwner {
        uint len = _towerPools.length;
        for (uint i; i < len; ++i) {
            TowerPool(_towerPools[i]).whitelistNotifiedRewards(_rewards[i]);
        }
    }

    function removeTowerPoolRewards(
        address[] calldata _towerPools,
        address[] calldata _rewards
    ) external onlyOwner {
        uint len = _towerPools.length;
        for (uint i; i < len; ++i) {
            TowerPool(_towerPools[i]).removeRewardWhitelist(_rewards[i]);
        }
    }

    struct TowerPoolInfo {
      address towerPool;
      address tokenForTowerPool;
      TowerPool.RewardInfo[] rewardInfoList;
      uint256 totalSupply;
      uint256 accountBalance;
      uint256[] earnedList;
    }

    function getInfoForAllTowerPools(address account) external view returns (TowerPoolInfo[] memory towerPoolInfoList) {
        uint256 len = allTowerPools.length;
        towerPoolInfoList = new TowerPoolInfo[](len);

        for (uint256 i = 0; i < len; i++) {
            address towerPoolAddress = allTowerPools[i];
            TowerPool towerPool = TowerPool(towerPoolAddress);
            towerPoolInfoList[i].totalSupply = towerPool.totalSupply();
            towerPoolInfoList[i].accountBalance = towerPool.balanceOf(account);
            towerPoolInfoList[i].towerPool = towerPoolAddress;
            towerPoolInfoList[i].tokenForTowerPool = towerPool.stake();
            towerPoolInfoList[i].rewardInfoList = towerPool.getRewardInfoList();
            towerPoolInfoList[i].earnedList = towerPool.earned(account);
        }
    }
}

