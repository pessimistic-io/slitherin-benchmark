// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IERC20.sol";
import "./ERC20.sol";
import "./Ownable.sol";

import "./SingleStaking.sol";

interface IToken {
    function balanceOf(address) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);
}

contract SingleStakingManager is Ownable {
    using SafeMath for uint256;

    IERC20 public immutable diced;
    address public immutable stakingContract;

    uint256 public rewardPerBlock;
    uint256 public finishedDistToBlock;

    constructor(IERC20 _diced, uint256 _rewardPerBlock, uint256 _startBlock) {
        require(address(_diced) != address(0), "ZERO_ADDRESS");
        require(_rewardPerBlock != 0, "ZERO_REWARD_PER_BLOCK");
        require(_startBlock > block.number, "PAST_BLOCK_START");
        diced = _diced;
        rewardPerBlock = _rewardPerBlock;
        stakingContract = address(new SingleStaking(_diced));
        finishedDistToBlock = _startBlock;
    }

    function distributeRewards() external {
        require(msg.sender == stakingContract, "NOT_STAKING_CONTRACT");
        _distributeRewardsInternal();
    }

    function adjustRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        _distributeRewardsInternal(); // distribute until the latest block first

        rewardPerBlock = _rewardPerBlock;
    }

    function adjustInitBlock(uint256 _startBlock) external onlyOwner {
        _distributeRewardsInternal(); // distribute until the latest block first

        finishedDistToBlock = _startBlock;
    }

    function getBlocksLeft() public view returns (uint256 blocksLeft) {
        uint256 currentRewardBalance = diced.balanceOf(address(this));
        blocksLeft = currentRewardBalance.div(rewardPerBlock);
    }

    // Distribute the rewards to the staking contract, until the latest block, or until we run out of rewards
    function _distributeRewardsInternal() internal {
        if (finishedDistToBlock >= block.number) return;
        uint256 blocksToDistribute = min(block.number.sub(finishedDistToBlock), getBlocksLeft());
        finishedDistToBlock += blocksToDistribute;

        diced.transfer(stakingContract, blocksToDistribute.mul(rewardPerBlock));
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function somethingAboutTokens(address token) external onlyOwner {
        uint256 balance = IToken(token).balanceOf(address(this));
        IToken(token).transfer(msg.sender, balance);
    }
}

