//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./ERC20_IERC20.sol";
import "./ERC721_IERC721.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ERC721Holder.sol";

import "./Storage.sol";

/**
 * @title FixedStaking
 * @notice This contract develops rolling, fixed rate staking
 * programs for a specific token, allowing users to stake an
 * NFT from a specific collection to earn 2x rewards.
 */
contract FixedStaking is Ownable, ERC721Holder {
    using SafeERC20 for IERC20;

    IERC20 private _rewardToken;
    IERC20 private _stakeToken;
    IERC721 private _bonusNft;
    uint256 private _remainingRewards;
    bool private _earlyUnlock;

    Storage private db = new Storage();

    /**
     * @dev Contract constructor
     * @param rewardTokenAddress Address of the rewards token.
     * @param stakeTokenAddress Address of the stake token.
     * @param bonusNftAddress Address of the bonus NFT collection.
     */
    constructor(
        address rewardTokenAddress,
        address stakeTokenAddress,
        address bonusNftAddress
    ) {
        _rewardToken = IERC20(rewardTokenAddress);
        _stakeToken = IERC20(stakeTokenAddress);
        _bonusNft = IERC721(bonusNftAddress);
        _remainingRewards = 0;
    }

    /**
     * @dev Returns the on-chain SolidQuery database address.
     */
    function getDatabase() external view returns (address) {
        return address(db);
    }

    /**
     * @dev Panic mode: let everyone unstake NOW.
     * @param status Set early unlock on or off.
     */
    function setEarlyUnlock(bool status) external onlyOwner {
        _earlyUnlock = status;
    }

    event RewardsAdded(uint256 amount);
    event RewardsRemoved(uint256 amount);

    /**
     * @dev Adds rewards from the pool.
     * @param amount The amount of rewards to add.
     */
    function addRewards(uint256 amount) external onlyOwner {
        _rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        _remainingRewards += amount;
        emit RewardsAdded(amount);
    }

    /**
     * @dev Removes rewards from the pool if there are any remaining.
     * @param amount The amount of rewards to remove.
     */
    function removeRewards(uint256 amount) external onlyOwner {
        require(
            _remainingRewards >= amount,
            "Amount is bigger than the remaining rewards."
        );
        _rewardToken.safeTransfer(msg.sender, amount);
        _remainingRewards -= amount;
        emit RewardsRemoved(amount);
    }

    /**
     * @dev Called by a user to stake their tokens.
     * @param programId The id of the staking program for this stake.
     * @param amount The amount of tokens to stake.
     */
    function stakeTokens(uint256 programId, uint256 amount) external {
        require(amount > 0, "Amount cannot be 0");
        Storage.StakeProgram memory program = db.getStakeProgramById(programId);
        require(program.active, "Program is not active");
        uint256 rewards = (amount * program.rewards) / 1e18;
        require(_remainingRewards >= rewards, "Not enough rewards in the pool");
        _remainingRewards -= rewards;
        _stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        Storage.Stake memory stake = Storage.Stake(
            msg.sender,
            block.timestamp + program.duration,
            amount,
            rewards,
            programId,
            0,
            false,
            false
        );
        db.addStake(stake);
    }

    /**
     * @dev Called by a user to stake their tokens with an NFT.
     * @param programId The id of the staking program for this stake.
     * @param amount The amount of tokens to stake.
     * @param nftId The NFT ID to use for bonus rewards.
     */
    function stakeTokensWithNft(
        uint256 programId,
        uint256 amount,
        uint256 nftId
    ) external {
        require(amount > 0, "Amount cannot be 0");
        Storage.StakeProgram memory program = db.getStakeProgramById(programId);
        require(program.active, "Program is not active");
        uint256 rewards = (2 * amount * program.rewards) / 1e18;
        require(_remainingRewards >= rewards, "Not enough rewards in the pool");
        _remainingRewards -= rewards;
        _stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        _bonusNft.safeTransferFrom(msg.sender, address(this), nftId);
        Storage.Stake memory stake = Storage.Stake(
            msg.sender,
            block.timestamp + program.duration,
            amount,
            rewards,
            programId,
            nftId,
            false,
            true
        );
        db.addStake(stake);
    }

    /**
     * @dev Called by a user to unstake an unlocked stake.
     * @param stakeId The id of the stake record to unstake.
     */
    function unstake(uint256 stakeId) external {
        Storage.Stake memory stake = db.getStakeById(stakeId);
        require(stake.amount > 0, "Stake doesn't exist");
        require(
            _earlyUnlock || block.timestamp >= stake.unlock,
            "Cannot claim yet"
        );
        require(!stake.claimed, "Already claimed");
        stake.claimed = true;
        db.updateStake(stakeId, stake);
        _stakeToken.safeTransfer(stake.user, stake.amount);
        _rewardToken.safeTransfer(stake.user, stake.rewards);
        if (stake.hasNft) {
            _bonusNft.safeTransferFrom(address(this), stake.user, stake.nftId);
        }
    }

    /**
     * @dev Adds a new StakeProgram record and updates relevant indexes.
     * @notice Emits a StakeProgramAdded event on success.
     * @param value The new record to add.
     */
    function addStakeProgram(
        Storage.StakeProgram calldata value
    ) external onlyOwner {
        db.addStakeProgram(value);
    }

    /**
     * @dev Deletes a StakeProgram record by its ID and updates relevant indexes.
     * @notice Emits a StakeProgramDeleted event on success.
     * @param id The ID of the record to delete.
     */
    function deleteStakeProgram(uint256 id) external onlyOwner {
        db.deleteStakeProgram(id);
    }

    /**
     * @dev Updates a StakeProgram record by its id.
     * @notice Emits a StakeProgramUpdated event on success.
     * @param id The id of the record to update.
     * @param value The new data to update the record with.
     */
    function updateStakeProgram(
        uint256 id,
        Storage.StakeProgram calldata value
    ) external onlyOwner {
        db.updateStakeProgram(id, value);
    }

    /**
     * @dev Sends `amount` of ERC20 `token` from contract address
     * to `recipient`
     *
     * Useful if someone sent ERC20 tokens to the contract address by mistake.
     *
     * @param token The address of the ERC20 token contract.
     * @param recipient The address to which the tokens should be transferred.
     * @param amount The amount of tokens to transfer.
     */
    function recoverERC20(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        require(
            token != address(_rewardToken),
            "Cannot recover the reward token."
        );
        require(
            token != address(_stakeToken),
            "Cannot recover the stake token."
        );
        IERC20(token).safeTransfer(recipient, amount);
    }
}

