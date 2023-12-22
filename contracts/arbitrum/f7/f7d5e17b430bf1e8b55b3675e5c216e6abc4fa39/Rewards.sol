// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./DataStore.sol";
import "./FundStore.sol";
import "./RewardStore.sol";

import "./Chainlink.sol";
import "./Roles.sol";

/**
 * @title  Rewards
 * @notice Implementation of rewards related logic
 */
contract Rewards is Roles {

    // Constants
    uint256 public constant UNIT = 10 ** 18;
    uint256 public constant BPS_DIVIDER = 10000;

    // Events
    event RewardIncremented(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event RewardClaimed(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    // Contracts
    DataStore public DS;

    FundStore public fundStore;
    RewardStore public rewardStore;

    Chainlink public chainlink;

    address constant TOKEN = 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB
    address constant TOKEN_CHAINLINK_FEED = 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6;

    uint256 public lastDailyReset;
    uint256 public dailyRewards;

    uint256 public feeBps = 1000;
    uint256 public maxDailyReward = 3000 * UNIT;

    /// @dev Initializes DataStore address
    constructor(RoleStore rs, DataStore ds) Roles(rs) {
        DS = ds;
    }

    /// @notice Initializes protocol contracts
    /// @dev Only callable by governance
    function link() external onlyGov {
        fundStore = FundStore(payable(DS.getAddress('FundStore')));
        rewardStore = RewardStore(DS.getAddress('RewardStore'));
        chainlink = Chainlink(DS.getAddress('Chainlink'));
    }

    function setFeeBps(uint256 bps) external onlyGov {
        require(bps < BPS_DIVIDER, '!bps');
        feeBps = bps;
    }

    function setMaxDailyReward(uint256 amount) external onlyGov {
        maxDailyReward = amount;
    }

    /// @notice Increases reward for a given user based on the fee they paid
    /// @dev Only callable by other protocol contracts
    function incrementReward(address user, uint256 feeUsd) public onlyContract {
        if (feeBps == 0) return;
        uint256 chainlinkPrice = chainlink.getPrice(TOKEN_CHAINLINK_FEED);
        uint256 amount = UNIT * feeUsd * feeBps / (chainlinkPrice * BPS_DIVIDER);
        
        if (lastDailyReset == 0) {
            lastDailyReset = block.timestamp;
        }
        if (lastDailyReset < block.timestamp - 1 days) {
            dailyRewards = 0;
            lastDailyReset = block.timestamp;
        }
        
        if (dailyRewards > maxDailyReward) return;

        dailyRewards += amount;

        rewardStore.incrementReward(user, TOKEN, amount);

        emit RewardIncremented(
            user,
            TOKEN,
            amount
        );
    }

    function claimReward() external {
        address user = msg.sender;
        uint256 userReward = rewardStore.getReward(user, TOKEN);
        if (userReward == 0) return;
        rewardStore.decrementReward(user, TOKEN, userReward);
        fundStore.transferOut(TOKEN, user, userReward);
        emit RewardClaimed(
            user,
            TOKEN,
            userReward
        );
    }

}

