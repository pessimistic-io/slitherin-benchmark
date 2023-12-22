//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "./Ownable.sol";
import { ERC20 } from "./ERC20.sol";
import { Stake, FeeDistributorInfo } from "./Structs.sol";
import { IERC20 } from "./IERC20.sol";
import { IPepeFeeDistributor } from "./IPepeFeeDistributor.sol";
import { IPepeStaking } from "./IPepeStaking.sol";
import { Math } from "./Math.sol";

///@author @JayusJay || https://github.com/jayusjay || Inspiration from SushiSwap Masterchef V2

contract PepeStaking is IPepeStaking, Ownable, ERC20 {
    ///@dev staking contract where users can stake $PEG to receive 30% of protocol fees
    ///@dev as $USDC rewards. Users can unstake at any time and claim their rewards.
    ///@dev rewards are distributed to users based on their share of peg staked.
    ///@dev rewards will come in streams to this contract and be distributed to users.

    using Math for uint256;
    using Math for int256;

    IERC20 public immutable pegToken;
    IERC20 public immutable usdcToken;

    IPepeFeeDistributor public feeDistributor;
    uint256 public totalStaked; ///@dev total peg staked.
    uint256 public accumulatedUsdcPerPeg; ///@dev cumulative usdc per peg staked.
    uint48 public lastUpdateRewardsTimestamp; ///@dev last time the staking rewards were updated.

    mapping(address user => Stake stake) public userStake;

    event Staked(address indexed user, uint256 indexed amount);
    event Unstaked(address indexed user, uint256 indexed amount);
    event Claimed(address indexed user, uint256 indexed amount);
    event FeeDistributorUpdated(address indexed feeDistributor);

    constructor(address _pegToken, address _usdcToken) ERC20("Pepe Staking Token", "sPEG") {
        pegToken = IERC20(_pegToken);
        usdcToken = IERC20(_usdcToken);
    }

    ///@notice transfers usdc allocated to this contract from the fee distributor and proportionally allocate it based on the total peg staked.
    function updateRewards() public override {
        if (totalStaked == 0) {
            lastUpdateRewardsTimestamp = uint48(block.timestamp);
            return;
        }
        if (uint48(block.timestamp) > lastUpdateRewardsTimestamp) {
            uint256 sharableUsdc = feeDistributor.allocateStake();
            if (sharableUsdc != 0) {
                uint256 usdcPerPeg = sharableUsdc.mulDiv(1e18, totalStaked);
                accumulatedUsdcPerPeg += usdcPerPeg;
            }
            lastUpdateRewardsTimestamp = uint48(block.timestamp);
        }
    }

    ///@notice stake $PEG to receive 10% of protocol fees as $USDC rewards.
    function stake(uint256 amount) public override {
        require(amount != 0, "!amount");
        require(address(feeDistributor) != address(0), "fee distributor not set");
        require(pegToken.transferFrom(msg.sender, address(this), amount), "transfer failed");

        updateRewards();

        userStake[msg.sender].amount += amount;
        userStake[msg.sender].rewardDebt += int256(amount.mulDiv(accumulatedUsdcPerPeg, 1e18));

        totalStaked += amount;
        _mint(msg.sender, amount);
        emit Staked(msg.sender, amount);
    }

    ///@notice unStake $PEG and claim rewards.
    function unStake(uint256 amount) public override {
        require(amount != 0, "!amount");
        require(userStake[msg.sender].amount >= amount, "insufficient stake");

        claimRewards();

        userStake[msg.sender].amount -= amount;
        userStake[msg.sender].rewardDebt -= int256(amount.mulDiv(accumulatedUsdcPerPeg, 1e18));

        totalStaked -= amount;
        _burn(msg.sender, amount);
        require(pegToken.transfer(msg.sender, amount), "transfer failed");
        emit Unstaked(msg.sender, amount);
    }

    ///@notice unstake all $PEG and claim rewards.
    function exit() public override {
        require(userStake[msg.sender].amount != 0, "no stake");
        unStake(userStake[msg.sender].amount);
    }

    ///@notice claim rewards without unstaking.
    function claimRewards() public override {
        require(address(feeDistributor) != address(0), "fee distributor not set");
        require(userStake[msg.sender].amount != 0, "no stake");
        updateRewards();

        int256 accumulatedUsdc = int256(userStake[msg.sender].amount.mulDiv(accumulatedUsdcPerPeg, 1e18));
        uint256 _pendingUsdc = uint256(accumulatedUsdc - userStake[msg.sender].rewardDebt);
        userStake[msg.sender].rewardDebt = accumulatedUsdc;

        if (_pendingUsdc != 0) {
            require(usdcToken.transfer(msg.sender, _pendingUsdc), "transfer failed");
            emit Claimed(msg.sender, _pendingUsdc);
        }
    }

    ///@notice returns the amount of $USDC rewards a user can claim.
    function pendingRewards(address _user) public view override returns (uint256) {
        if (totalStaked == 0 || userStake[_user].amount == 0) {
            return 0;
        }
        FeeDistributorInfo memory feeDistributorInfo;
        feeDistributorInfo.lastUpdateTimestamp = feeDistributor.getLastUpdatedTimestamp();
        feeDistributorInfo.accumulatedUsdcPerContract = feeDistributor.getAccumulatedUsdcPerContract();
        feeDistributorInfo.lastBalance = feeDistributor.getLastBalance();
        feeDistributorInfo.stakingContractDebt = feeDistributor.getShareDebt(address(this));
        feeDistributorInfo.currentBalance = usdcToken.balanceOf(address(feeDistributor));

        if (uint48(block.timestamp) > feeDistributorInfo.lastUpdateTimestamp) {
            uint256 diff = feeDistributorInfo.currentBalance - feeDistributorInfo.lastBalance;
            if (diff != 0) {
                feeDistributorInfo.accumulatedUsdcPerContract += diff / 1e4;
            }
        }
        (uint256 stakingContractShare, , ) = feeDistributor.getContractShares();

        int256 accumulatedStakingUsdc = int256(stakingContractShare * feeDistributorInfo.accumulatedUsdcPerContract);
        uint256 pendingStakingUsdc = uint256(accumulatedStakingUsdc - feeDistributorInfo.stakingContractDebt);

        uint256 pepeStakingAccumulatedUsdcPerPeg = accumulatedUsdcPerPeg;
        if (pendingStakingUsdc != 0) {
            ///@notice sharable usdc = pendingStakingUsdc
            pepeStakingAccumulatedUsdcPerPeg += pendingStakingUsdc.mulDiv(1e18, totalStaked);
        }

        int256 accumulatedUsdc = int256(userStake[_user].amount.mulDiv(pepeStakingAccumulatedUsdcPerPeg, 1e18));
        uint256 _pendingUsdc = uint256(accumulatedUsdc - userStake[_user].rewardDebt);
        return _pendingUsdc;
    }

    ///@notice transfers are not allowed.
    function _transfer(address, address, uint256) internal pure override {
        require(false, "transfer not allowed");
    }

    ///@notice returns the amount of $PEG a user has staked.
    function getUserStake(address _user) public view override returns (uint256) {
        return userStake[_user].amount;
    }

    function setFeeDistributor(address _feeDistributor) external override onlyOwner {
        require(_feeDistributor != address(0), "!address");
        feeDistributor = IPepeFeeDistributor(_feeDistributor);
        emit FeeDistributorUpdated(_feeDistributor);
    }
}

