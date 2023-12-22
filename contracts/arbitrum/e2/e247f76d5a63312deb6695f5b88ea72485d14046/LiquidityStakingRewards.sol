// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC721Enumerable} from "./IERC721Enumerable.sol";
import {IERC20} from "./IERC20.sol";

import {SafeMath} from "./SafeMath.sol";
import {Math} from "./Math.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC721Holder} from "./ERC721Holder.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

// Inheritance
import {ILiquidityStakingRewards} from "./ILiquidityStakingRewards.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";

import {BaseRecipient} from "./BaseRecipient.sol";

import {PeripheryPayments} from "./PeripheryPayments.sol";

contract LiquidityStakingRewards is ILiquidityStakingRewards, PeripheryPayments, ERC721Holder, ReentrancyGuard, BaseRecipient {

    using SafeMath for uint256;

    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    address public immutable positionManagerAddress;

    uint256 public immutable liquidityTokenId;

    IERC20 public rewardsToken;

    uint256 public periodFinish = 0;

    uint256 public rewardRate = 0;

    uint256 public rewardsDuration = 1 days;

    uint256 public lastUpdateTime;

    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;

    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);

    event Staked(address indexed user, uint256 amount);

    event Withdrawn(address indexed user, uint256 amount);

    event RewardPaid(address indexed user, uint256 reward);

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address positionManagerAddress_,
        address rewardsToken_,
        address WETH9_,
        uint256 liquidityTokenId_,
        address recipient_
    )   PeripheryPayments(WETH9_)
        BaseRecipient(recipient_) {
        positionManagerAddress = positionManagerAddress_;
        liquidityTokenId = liquidityTokenId_;
        rewardsToken = IERC20(rewardsToken_);
        //
        _transferOwnership(_msgSender());
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
        );
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function increaseLiquidityStake(INonfungiblePositionManager.IncreaseLiquidityParams calldata params) external payable
        nonReentrant
        updateReward(_msgSender())
        isValid(params.amount0Desired, params.amount1Desired) {
        // positions
        (,,address token0,address token1,,,,,,,,) = INonfungiblePositionManager(positionManagerAddress).positions(liquidityTokenId);
        // receipt
        receipt(token0, _msgSender(), address(this), params.amount0Desired);
        receipt(token1, _msgSender(), address(this), params.amount1Desired);
        // approve
        approve(token0, positionManagerAddress, params.amount0Desired);
        approve(token1, positionManagerAddress, params.amount1Desired);
        // increaseLiquidity
        (uint128 newIncreaseLiquidity, ,) = INonfungiblePositionManager(positionManagerAddress).increaseLiquidity{value : msg.value}(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId : liquidityTokenId,
                amount0Desired : params.amount0Desired,
                amount1Desired : params.amount1Desired,
                amount0Min : params.amount0Min,
                amount1Min : params.amount1Min,
                deadline : params.deadline
            })
        );
        //
        require(newIncreaseLiquidity > 0, "LiquidityStakingRewards: Cannot stake 0");
        _totalSupply = _totalSupply.add(newIncreaseLiquidity);
        _balances[_msgSender()] = _balances[_msgSender()].add(newIncreaseLiquidity);
        //
        emit Staked(_msgSender(), newIncreaseLiquidity);
    }

    function decreaseLiquidityStake(uint128 liquidityAmount, uint256 amount0Min, uint256 amount1Min) public
        nonReentrant
        updateReward(_msgSender())
        isValid(amount0Min, amount1Min) {
        //
        require(liquidityAmount > 0, "LiquidityStakingRewards: cannot withdraw 0");
        require(_balances[_msgSender()] >= liquidityAmount, "LiquidityStakingRewards: insufficient liquidity");
        //
        _totalSupply = _totalSupply.sub(liquidityAmount);
        _balances[_msgSender()] = _balances[_msgSender()].sub(liquidityAmount);

        //
        (uint256 decreaseLiquidityAmount0, uint256 decreaseLiquidityAmount1) = INonfungiblePositionManager(positionManagerAddress).decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId : liquidityTokenId,
                liquidity : liquidityAmount,
                amount0Min : amount0Min,
                amount1Min : amount1Min,
                deadline : (block.timestamp + 120)
            })
        );

        (uint256 collectAmount0, uint256 collectAmount1) = INonfungiblePositionManager(positionManagerAddress).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId : liquidityTokenId,
                recipient : address(this),
                amount0Max : type(uint128).max,
                amount1Max : type(uint128).max
            })
        );

        if (collectAmount0 > 0 || collectAmount1 > 0) {
            (,,address token0, address token1,,,,,,,,) = INonfungiblePositionManager(positionManagerAddress).positions(liquidityTokenId);

            if (collectAmount0 > 0) {
                if (collectAmount0 >= decreaseLiquidityAmount0) {
                    IERC20(token0).safeTransfer(_msgSender(), decreaseLiquidityAmount0);
                    uint256 residueAmount0 = collectAmount0.sub(decreaseLiquidityAmount0);
                    if (residueAmount0 > 0) {
                        IERC20(token0).safeTransfer(recipient, residueAmount0);
                    }
                } else {
                    IERC20(token0).safeTransfer(recipient, collectAmount0);
                }
            }

            if (collectAmount1 > 0) {
                if (collectAmount1 >= decreaseLiquidityAmount1) {
                    IERC20(token1).safeTransfer(_msgSender(), decreaseLiquidityAmount1);
                    uint256 residueAmount1 = collectAmount1.sub(decreaseLiquidityAmount1);
                    if (residueAmount1 > 0) {
                        IERC20(token1).safeTransfer(recipient, residueAmount1);
                    }
                } else {
                    IERC20(token1).safeTransfer(recipient, collectAmount1);
                }
            }
        }
    }

    function claimReward() public nonReentrant updateReward(_msgSender()) {
        uint256 reward = rewards[_msgSender()];
        if (reward > 0) {
            rewards[_msgSender()] = 0;
            rewardsToken.safeTransfer(_msgSender(), reward);
            emit RewardPaid(_msgSender(), reward);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward, uint256 rewardsDuration_) external onlyOwner updateReward(address(0)) {

        require(rewardsDuration_ > 0 , "LiquidityStakingRewards: rewards duration is zero");

        rewardsDuration = rewardsDuration_;

        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardsToken.balanceOf(address(this));
        require(rewardRate <= balance.div(rewardsDuration), "LiquidityStakingRewards: Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier isValid(uint256 token0Amount, uint256 token1Amount) {
        require(token0Amount > 0 && token1Amount > 0, "LiquidityStakingRewards: token amount must greater than 0");
        require(IERC721Enumerable(positionManagerAddress).ownerOf(liquidityTokenId) == address(this), "LiquidityStakingRewards: not token owner");
        _;
    }

}

