// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Owned.sol";
import "./IChef.sol";
import "./IMintPool.sol";
import "./Vars.sol";
import "./UUPSUpgradeableExp.sol";

contract SO3Chef is IChef, UUPSUpgradeableExp {
    struct UserInfo {
        address host;
        uint256 amount;
        uint256 index;
        uint256 unclaimed;
    }

    event Deposit(address indexed user, uint256 amount);
    event Withraw(address indexed user, uint256 amount);
    event RewardPerBlock(uint256 amount);
    event Claim(address indexed user, address host, uint256 amount, uint256 toMiner, uint256 toTreasury);
    event FeePointChanged(uint256 toTreasury, uint256 toMiner);
    event TreasuryChanged(address newTreasury);

    IMintPool public so3Miner;
    uint256 public rewardPerBlock;
    uint256 public lastRewardBlock;
    uint256 public perShareIndex;
    uint256 public totalDeposits;
    uint256 public startBlock_deleted;
    uint256 public mintFeeBP;
    uint256 public mintFeeToMinerBP;
    address public agent;
    address public treasury;
    mapping(address => UserInfo) public userInfo;

    function initialize(IMintPool so3Miner_, address agent_, address treasury_, uint256 rewardPerBlock_)
        external
        initializer
    {
        so3Miner = so3Miner_;
        agent = agent_;
        rewardPerBlock = rewardPerBlock_;
        lastRewardBlock = block.timestamp;
        treasury = treasury_;
        mintFeeBP = 200; //2%
        mintFeeToMinerBP = 800; //8%

        _init();

        emit RewardPerBlock(rewardPerBlock);
        emit TreasuryChanged(treasury);
    }

    function unclaimed(address acct) public view returns (uint256 debt) {
        UserInfo memory user = userInfo[acct];

        unchecked {
            debt = user.unclaimed + ((user.amount * (perShareIndex - user.index)) / TIMES);
        }
    }

    function unclaimed(address[] calldata accounts) external returns (uint256 sum) {
        _update();

        for (uint256 i = 0; i < accounts.length; i++) {
            sum += unclaimed(accounts[i]);
        }
    }

    function deposit(address acct, address host, uint256 amount) external override {
        if (msg.sender != agent) revert INVALID_CHEF_AGENT();
        _updateUser(acct);

        address currHost = userInfo[acct].host;
        if (currHost == address(0)) {
            userInfo[acct].host = host;
        } else if (currHost != host) {
            revert HOST_MISMATCH();
        }
        unchecked {
            userInfo[acct].amount += amount;
        }
        totalDeposits += amount;
    }

    function withdraw(address acct, uint256 amount) external {
        if (msg.sender != agent) revert INVALID_CHEF_AGENT();
        _updateUser(acct);

        userInfo[acct].amount -= amount;
        totalDeposits -= amount;
        emit Withraw(acct, amount);
    }

    function setHost(address acct, address host) external override {
        if (msg.sender != agent) revert INVALID_CHEF_AGENT();
        userInfo[acct].host = host;
    }

    function claim() external {
        _claim(msg.sender);
    }

    function claim(address[] calldata accounts) external override {
        for (uint256 i = 0; i < accounts.length; i++) {
            _claim(accounts[i]);
        }
    }

    // --------------- administrator function -----------

    function setRewardPerBlock(uint256 amount) external onlyOwner {
        _update();
        rewardPerBlock = amount;
        emit RewardPerBlock(amount);
    }

    function setAgent(address newAgent) external onlyOwner {
        if (newAgent == address(0)) revert ADDRESS_IS_EMPTY();
        agent = newAgent; //ignore event
    }

    function setSO3(IMintPool miner) external onlyOwner {
        if (address(miner) == address(0)) revert ADDRESS_IS_EMPTY();
        so3Miner = miner;
    }

    function setFeeBP(uint256 toMiner, uint256 toTreasury) external onlyOwner {
        require(toMiner + toTreasury < BP);
        mintFeeBP = toTreasury;
        mintFeeToMinerBP = toMiner;

        emit FeePointChanged(toTreasury, toMiner);
    }

    function setTreasury(address addr) external onlyOwner {
        if (addr == address(0)) revert ADDRESS_IS_EMPTY();

        treasury = addr;
        emit TreasuryChanged(addr);
    }

    // --------------- administrator function end -----------
    // --------------- private function -----------
    function _claim(address acct) private {
        _updateUser(acct);

        uint256 debt = userInfo[acct].unclaimed;
        if (debt == 0) return;

        userInfo[acct].unclaimed = 0;

        unchecked {
            uint256 feeToMiner = (debt * mintFeeToMinerBP) / BP;
            uint256 feeToTreasury = (debt * mintFeeBP) / BP;
            if (feeToTreasury > 0) so3Miner.mint(treasury, feeToTreasury);
            if (feeToMiner > 0) so3Miner.mint(acct, feeToMiner);
            so3Miner.mint(userInfo[acct].host, debt - feeToTreasury - feeToMiner);

            emit Claim(acct, userInfo[acct].host, debt, feeToMiner, feeToTreasury);
        }
    }

    function _update() private {
        if (block.timestamp <= lastRewardBlock || totalDeposits == 0) return;

        unchecked {
            uint256 rewards = (block.timestamp - lastRewardBlock) * rewardPerBlock;

            perShareIndex += (rewards * TIMES) / totalDeposits;
        }

        lastRewardBlock = block.timestamp;
    }

    function _updateUser(address acct) private {
        _update();
        userInfo[acct].unclaimed = unclaimed(acct);
        userInfo[acct].index = perShareIndex;
    }

    // --------------- private function end -----------
}

