//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { Ownable } from "./Ownable.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { EsPegStake } from "./Structs.sol";
import { IEsPepeToken } from "./IEsPepeToken.sol";
import { IPepeEsPegStaking } from "./IPepeEsPegStaking.sol";
import { IPepeEsPegRewardPool } from "./IPepeEsPegRewardPool.sol";

contract PepeEsPegStaking is IPepeEsPegStaking, ERC20("Pepe EsPeg Staking Token", "sESPEG"), Ownable {
    using SafeERC20 for IERC20;
    uint256 public constant MINIMUM_STAKE = 1e18; //1 esPeg
    uint48 public constant STAKE_VESTING_DURATION = 90 days;

    IERC20 public immutable pegToken; //reward token
    IEsPepeToken public immutable esPegToken; //underlying token
    IPepeEsPegRewardPool public rewardPool; // rewardPool contract.

    mapping(address user => mapping(uint256 stakeId => EsPegStake)) public stakes;
    mapping(address user => uint256 stakeId) public userStakeCount;

    event Stake(address indexed user, uint256 amount, uint256 pegPerSecond, uint48 startTime, uint48 fullVestingTime);
    event Claimed(address indexed user, uint256 amount);
    event RewardsVested(address indexed user, uint256 indexed amount, uint256 indexed stakeId);

    constructor(address esPegToken_, address pegToken_, address rewardPool_) {
        esPegToken = IEsPepeToken(esPegToken_);
        pegToken = IERC20(pegToken_);
        rewardPool = IPepeEsPegRewardPool(rewardPool_);
    }

    ///@notice stake/vest esPeg tokens for 3 months for peg rewards
    ///@param amount amount of esPeg to stake
    function stake(uint256 amount) external override {
        require(amount > MINIMUM_STAKE, "too little");
        require(esPegToken.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        uint256 pegPerSecond = amount / STAKE_VESTING_DURATION;
        uint256 userStakeCount_ = ++userStakeCount[msg.sender];

        stakes[msg.sender][userStakeCount_] = EsPegStake({
            user: msg.sender,
            amount: amount,
            amountClaimable: amount,
            amountClaimed: 0,
            pegPerSecond: pegPerSecond,
            startTime: uint48(block.timestamp),
            fullVestingTime: uint48(block.timestamp + STAKE_VESTING_DURATION),
            lastClaimTime: uint48(block.timestamp)
        });

        //allocate peg rewards
        rewardPool.allocatePegStaking(amount);

        _mint(msg.sender, amount);
        emit Stake(
            msg.sender,
            amount,
            pegPerSecond,
            uint48(block.timestamp),
            uint48(block.timestamp + STAKE_VESTING_DURATION)
        );
    }

    ///@notice claim all rewards for all stakes
    function claimAll() external override {
        uint256 userStakeCount_ = userStakeCount[msg.sender];
        uint256 i = 1;
        for (; i <= userStakeCount_; ) {
            claim(i);
            unchecked {
                ++i;
            }
        }
    }

    ///@notice claim rewards for a specific stake
    ///@param stakeId id of the stake to claim rewards for
    function claim(uint256 stakeId) public override {
        require(stakeId != 0, "Invalid stake Id");
        EsPegStake memory stake_ = stakes[msg.sender][stakeId];
        require(stake_.user == msg.sender, "Invalid user");

        if (stake_.amountClaimed >= stake_.amountClaimable) {
            emit RewardsVested(msg.sender, stake_.amountClaimed, stakeId);
            return;
        }

        if (uint48(block.timestamp) > stake_.lastClaimTime) {
            stakes[msg.sender][stakeId].lastClaimTime = uint48(block.timestamp);

            uint256 amountToClaim = (uint48(block.timestamp) - stake_.lastClaimTime) * stake_.pegPerSecond;

            if (amountToClaim > stake_.amountClaimable - stake_.amountClaimed) {
                amountToClaim = stake_.amountClaimable - stake_.amountClaimed;
            }

            stakes[msg.sender][stakeId].amountClaimed += amountToClaim;

            _burn(msg.sender, amountToClaim); ///burn receipt tokens
            esPegToken.burn(address(this), amountToClaim); ///burn esPeg tokens

            require(pegToken.transfer(msg.sender, amountToClaim), "transfer failed");
            emit Claimed(msg.sender, amountToClaim);
        }
    }

    ///@notice get pending rewards for a user
    ///@param user user to get pending rewards for
    function pendingRewards(address user) external view override returns (uint256 pendingRewards_) {
        uint256 userStakeCount_ = userStakeCount[user];
        uint256 i = 1;
        pendingRewards_;

        for (; i <= userStakeCount_; ) {
            EsPegStake memory stake_ = stakes[user][i];

            if (stake_.amountClaimed >= stake_.amountClaimable) continue;

            if (uint48(block.timestamp) > stake_.lastClaimTime) {
                uint256 amountToClaim = (uint48(block.timestamp) - stake_.lastClaimTime) * stake_.pegPerSecond;

                if (amountToClaim > stake_.amountClaimable - stake_.amountClaimed) {
                    amountToClaim = stake_.amountClaimable - stake_.amountClaimed;
                }

                pendingRewards_ += amountToClaim;
            }
            unchecked {
                ++i;
            }
        }
    }

    ///@notice get stake info for a user
    ///@param user user to get stake info for
    function getUserStake(address user, uint256 stakeId) external view override returns (EsPegStake memory) {
        return stakes[user][stakeId];
    }

    function updateRewardPoolContract(address _rewardPool) public onlyOwner {
        rewardPool = IPepeEsPegRewardPool(_rewardPool);
    }

    /// @dev retrieve stuck tokens
    function retrieve(address _token) external onlyOwner {
        require(_token != address(this), "Underlying Token");
        IERC20 token = IERC20(_token);
        if (address(this).balance != 0) {
            (bool success, ) = payable(owner()).call{ value: address(this).balance }("");
            require(success, "Retrieval Failed");
        }

        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }
}

