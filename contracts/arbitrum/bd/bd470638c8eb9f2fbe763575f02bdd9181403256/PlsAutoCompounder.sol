//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "./Ownable.sol";
import { StakeDetails } from "./Structs.sol";
import { IERC20 } from "./IERC20.sol";
import { IPlutusEpochStaking } from "./IPlutusEpochStaking.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Math } from "./Math.sol";
import { IPlsAutoCompounder } from "./IPlsAutoCompounder.sol";

contract PlsAutoCompounder is IPlsAutoCompounder, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint112;
    using Math for uint256;
    using Math for int256;

    address public constant EPOCH_REWARDS_PROXY = 0xbe68e51f75F34D8BC06D422056af117b8c23fd54;
    address public constant PLUTUS_BRIBE_PROXY = 0x24F11B6e5B21CAb23a8324438a4156FB96eBB0A5;

    IPlutusEpochStaking public immutable plutusOneMonthEpochStaking;
    IERC20 public immutable plsToken;
    address public immutable kyberSwapRouter;

    uint256 public totalPlsStaked;
    uint256 public accumulatedPlsPerPlsStaked;
    bool public isCompounding;

    mapping(address user => StakeDetails) public plsStakeDetails;
    mapping(address user => uint112) public plsRewardsBalance;

    event PlsStaked(address indexed user, uint32 indexed epoch, uint112 indexed plsStaked);
    event AllPlsStaked(uint256 indexed plsStaked, uint32 indexed epoch);
    event PlsUnstaked(address indexed user, uint32 indexed epoch);
    event AllPlsUnstaked(uint256 indexed plsUnstaked, uint32 indexed epoch);
    event PlsAssetsClaimed(address indexed owner);
    event PlsBribesClaimed(address indexed owner);
    event PlsRewardsAccumulated(address indexed owner, uint256 indexed accumulatedPlsPerPlsStaked);
    event PlsRewardsUpdated(address indexed user, uint256 indexed plsRewards);
    event PlsRewardsClaimed(address indexed user, uint256 indexed plsRewardsWithdrawn);
    event KyberSwapFailed(address indexed token, bytes indexed swapData);

    constructor(address _pls, address _plutusOneMonthEpochStaking, address _kyberSwapRouter) {
        plsToken = IERC20(_pls);
        plutusOneMonthEpochStaking = IPlutusEpochStaking(_plutusOneMonthEpochStaking);
        kyberSwapRouter = _kyberSwapRouter;
    }

    ///@notice user stakes PLS.
    function stakePls(uint112 amount) external override {
        require(amount != 0, "!amount");
        require(plutusOneMonthEpochStaking.stakingWindowOpen(), "staking window not open");

        plsToken.safeTransferFrom(msg.sender, address(this), amount);

        updatePlsRewards();

        if (plsToken.allowance(address(this), address(plutusOneMonthEpochStaking)) < amount) {
            plsToken.approve(address(plutusOneMonthEpochStaking), type(uint256).max);
        }

        plutusOneMonthEpochStaking.stake(amount);

        totalPlsStaked += amount;

        uint32 currentPlutusStakingEpoch = plutusOneMonthEpochStaking.currentEpoch();

        if (plsStakeDetails[msg.sender].plsStaked == 0) {
            plsStakeDetails[msg.sender] = StakeDetails({
                rewardDebt: int256(amount.mulDiv(accumulatedPlsPerPlsStaked, 1e18)),
                epoch: currentPlutusStakingEpoch,
                plsStaked: amount,
                user: msg.sender
            });
        } else {
            plsStakeDetails[msg.sender].rewardDebt += int256(amount.mulDiv(accumulatedPlsPerPlsStaked, 1e18));
            plsStakeDetails[msg.sender].epoch = currentPlutusStakingEpoch;
            plsStakeDetails[msg.sender].plsStaked += amount;
        }

        emit PlsStaked(msg.sender, currentPlutusStakingEpoch, amount);
    }

    ///@notice user unstakes and claims all the accumulated PLS rewards
    function unStakePls() external override {
        require(plutusOneMonthEpochStaking.stakedDetails(address(this)).amount == 0, "!Active Stake");
        require(plsStakeDetails[msg.sender].plsStaked != 0, "!No User Stake");

        updatePlsRewards();
        uint256 stakedAmount = plsStakeDetails[msg.sender].plsStaked;
        uint256 rewardsBalance = plsRewardsBalance[msg.sender];
        uint256 totalAmount = stakedAmount + rewardsBalance;

        if (totalAmount != 0) {
            // Delete user stake details
            delete plsStakeDetails[msg.sender];
            plsRewardsBalance[msg.sender] = 0;
            totalPlsStaked -= stakedAmount;

            // Transfer staked and reward PLS tokens to the user
            plsToken.safeTransfer(msg.sender, totalAmount);
            emit PlsUnstaked(msg.sender, plutusOneMonthEpochStaking.currentEpoch() - 1);
        }
    }

    /**
     * @notice accumulates PLS from bribes and swaps them for the PLS rewards
     * PLS is distributed to all the stakers and users may choose to withdraw their PLS rewards leaving the initial staked PLS
     * Require this contract is not currently compounding else all PLS would be in PLS and not here.
     */
    function claimPlsRewards() external override {
        require(plutusOneMonthEpochStaking.stakedDetails(address(this)).amount == 0, "active accumulator stake");

        updatePlsRewards();
        uint256 pendingPlsRewards = plsRewardsBalance[msg.sender];

        if (pendingPlsRewards != 0) {
            plsRewardsBalance[msg.sender] = 0;
            plsToken.safeTransfer(msg.sender, pendingPlsRewards);

            emit PlsRewardsClaimed(msg.sender, pendingPlsRewards);
        }
    }

    ///@param staker staker address
    function calculatePendingRewards(address staker) public view override returns (uint256) {
        StakeDetails memory userStake = plsStakeDetails[staker];

        if (userStake.plsStaked == 0) {
            return 0;
        }

        int256 plsAccumulated = int256(accumulatedPlsPerPlsStaked.mulDiv(userStake.plsStaked, 1e18));
        uint256 pendingRewards = uint256(plsAccumulated - userStake.rewardDebt);

        return pendingRewards;
    }

    function updatePlsRewards() public override {
        if (totalPlsStaked == 0) return;

        if (plsStakeDetails[msg.sender].plsStaked == 0) return;

        int256 plsAccumulated = int256(accumulatedPlsPerPlsStaked.mulDiv(plsStakeDetails[msg.sender].plsStaked, 1e18));
        uint256 pendingPlsRewards = uint256(plsAccumulated - plsStakeDetails[msg.sender].rewardDebt);
        plsStakeDetails[msg.sender].rewardDebt += plsAccumulated;

        if (pendingPlsRewards != 0) {
            plsRewardsBalance[msg.sender] += uint112(pendingPlsRewards);
        }

        emit PlsRewardsUpdated(msg.sender, pendingPlsRewards);
    }

    ///@notice admin functions

    ///@notice stakes all Pls in the contract.
    function stakeAllPls() external override onlyOwner {
        updatePlsRewards();

        uint112 amountToStake = uint112(plsToken.balanceOf(address(this)));

        if (amountToStake != 0) {
            if (plutusOneMonthEpochStaking.stakingWindowOpen()) {
                plsToken.approve(address(plutusOneMonthEpochStaking), type(uint256).max);
                plutusOneMonthEpochStaking.stake(amountToStake);
            }
            isCompounding = true;
            emit AllPlsStaked(amountToStake, plutusOneMonthEpochStaking.currentEpoch());
        }
    }

    ///@notice unstake all pls.
    function unStakeAllPls() external override onlyOwner {
        plutusOneMonthEpochStaking.unstake();
        isCompounding = false;
        emit AllPlsUnstaked(totalPlsStaked, plutusOneMonthEpochStaking.currentEpoch() - 1);
    }

    function adminUnstakeAndClaimPlsAssetsAndBribes() external override onlyOwner {
        claimPlsAssets();
        claimPlsBribes();
        plutusOneMonthEpochStaking.unstake();

        emit AllPlsUnstaked(totalPlsStaked, plutusOneMonthEpochStaking.currentEpoch() - 1);
    }

    ///@notice to be called before accumulatePls(swap,token)
    function claimPlsAssets() public override onlyOwner {
        //solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = EPOCH_REWARDS_PROXY.call(abi.encodeWithSignature("claimRewards()"));
        require(success, "claimPlsAssets: call failed");
        emit PlsAssetsClaimed(msg.sender);
    }

    ///@notice to be called before accumulatePls(swap,token)
    ///@notice claim bribes
    function claimPlsBribes() public override onlyOwner {
        //solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = PLUTUS_BRIBE_PROXY.call(abi.encodeWithSignature("claimAllRewards()"));
        require(success, "claimBribes: call failed");
        emit PlsBribesClaimed(msg.sender);
    }

    ///@param swapData data for swap
    ///@param tokens tokens to swap
    ///@notice to be called after claimPlsAssets() and claimPlsBribes().
    function accumulatePls(bytes[] calldata swapData, address[] calldata tokens) external override onlyOwner {
        require(swapData.length == tokens.length, "input length mismatch");
        uint256 tokensLength = tokens.length;
        uint256 i;
        for (; i < tokensLength; ) {
            if (IERC20(tokens[i]).allowance(address(this), kyberSwapRouter) == 0) {
                IERC20(tokens[i]).safeApprove(kyberSwapRouter, type(uint256).max);
            }
            unchecked {
                ++i;
            }
        }

        uint256 j;

        for (; j < tokensLength; ) {
            //solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = kyberSwapRouter.call(swapData[j]);

            if (!success) emit KyberSwapFailed(tokens[j], swapData[j]);

            unchecked {
                ++j;
            }
        }

        /**
         * @dev if we are compounding, all pls has been sent to plutus hence we need only read the balance of the contract to get accumulated pls.
         * if we are not compounding, we need to subtract the total pls staked from the balance of the contract to get the accumulated pls
         * because during uncompounding, all pls is unstaked and sent back to this contract.
         */
        uint256 plsAccumulated = isCompounding
            ? plsToken.balanceOf(address(this))
            : plsToken.balanceOf(address(this)) - totalPlsStaked;

        accumulatedPlsPerPlsStaked += plsAccumulated.mulDiv(1e18, totalPlsStaked);

        emit PlsRewardsAccumulated(msg.sender, plsAccumulated);
    }
}

