// SPDX-License-Identifier: GPL-2.0-or-later
// (C) Florence Finance, 2022 - https://florence.finance/
pragma solidity 0.8.17;

import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";

import "./FlorinToken.sol";
import "./FlorinTreasury.sol";
import "./Util.sol";
import "./Errors.sol";

contract FlorinStaking is OwnableUpgradeable, PausableUpgradeable {
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    IERC20MetadataUpgradeable public mediciToken;

    IERC20MetadataUpgradeable public florinToken;

    uint256 public mdcPerFLRperSecond;

    mapping(address => WalletStakingState) private walletStakingStates;

    uint256 public totalShares;

    uint256 public totalStakedFlorinTokens;

    struct WalletStakingState {
        uint256 stakedShares;
        uint256 stakedFlorinTokens;
        uint256 unclaimedRewardsSnapshotTimestamp;
        uint256 unclaimedRewardsSnapshot;
    }

    event Withdraw(address indexed receiver, uint256 florinTokens);
    event SetMDCperFLRperSecond(uint256 mdcPerFLRperSecond);
    event Stake(address indexed staker, uint256 florinTokens, uint256 shares);
    event Unstake(address indexed staker, uint256 requestedFlorinTokens, uint256 receivedFlorinTokens, uint256 eligibleShares);
    event Claim(address indexed staker, uint256 mediciTokens);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {} // solhint-disable-line

    function initialize(IERC20MetadataUpgradeable florinToken_, IERC20MetadataUpgradeable mediciToken_) external initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        _pause();
        florinToken = florinToken_;
        mediciToken = mediciToken_;
    }

    /// @dev Pauses the Florin Vault when not paused (only owner)
    function pause() external onlyOwner {
        _pause();
    }

    /// @dev Unpauses the Florin Vault when paused (only owner)
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev Owner can withdraw Florin to a specific loanVault in which a loan default occurred
    /// @param florinTokens Amount of Florin
    /// @param receiver Receiver address - normally the address of the Loan Vault with the loan default
    function withdraw(uint256 florinTokens, address receiver) external onlyOwner {
        florinToken.safeTransfer(receiver, florinTokens);
        emit Withdraw(receiver, florinTokens);
    }

    /// @dev Sets the amount of MDC reward token per staked FLR per block
    /// @param mdcPerFLRperSecond_ Amount of MDC reward token per staked FLR token per block
    function setMDCperFLRperSecond(uint256 mdcPerFLRperSecond_) external onlyOwner {
        mdcPerFLRperSecond = mdcPerFLRperSecond_;
        emit SetMDCperFLRperSecond(mdcPerFLRperSecond_);
    }

    /// @dev FLR token owner can stake their assets into Florin Vault and receive shares (only when contract not paused)
    /// @notice Emits event Stake
    /// @param florinTokens Amount of FLR token to stake
    function stake(uint256 florinTokens) public whenNotPaused {
        if (florinTokens == 0) {
            revert Errors.StakeAmountMustBeGreaterThanZero();
        }

        WalletStakingState storage walletStakingState = walletStakingStates[_msgSender()];
        _snapshotRewards(walletStakingState);

        uint256 shares = _convertToShares(florinTokens);
        walletStakingState.stakedShares += shares;
        walletStakingState.stakedFlorinTokens += florinTokens;

        totalStakedFlorinTokens += florinTokens;
        totalShares += shares;

        florinToken.safeTransferFrom(_msgSender(), address(this), florinTokens);
        emit Stake(_msgSender(), florinTokens, shares);
    }

    /// @dev Florin Vault Shares owner can unstake their staked assets (only when contract not paused)
    /// @notice Emits event Unstake
    /// @param requestedFlorinTokens Amount of FLR token to unstake
    function unstake(uint256 requestedFlorinTokens) public whenNotPaused {
        WalletStakingState storage walletStakingState = walletStakingStates[_msgSender()];

        uint256 requestedShares = _convertToShares(requestedFlorinTokens);

        uint256 eligibleShares = MathUpgradeable.min(requestedShares, walletStakingState.stakedShares);

        if (eligibleShares == 0) {
            revert Errors.EligibleSharesMustBeGreaterThanZero();
        }

        uint256 florinTokens = _convertToFlorinTokens(eligibleShares);

        _snapshotRewards(walletStakingState);

        walletStakingState.stakedShares -= eligibleShares;
        walletStakingState.stakedFlorinTokens -= florinTokens;

        totalStakedFlorinTokens -= florinTokens;
        totalShares -= eligibleShares;

        florinToken.safeTransfer(_msgSender(), florinTokens);
        emit Unstake(_msgSender(), requestedFlorinTokens, florinTokens, eligibleShares);
    }

    /// @dev Internal function that updates the outstanding MDC reward token
    /// @param walletStakingState The wallet staking state struct
    function _snapshotRewards(WalletStakingState storage walletStakingState) internal {
        if (walletStakingState.unclaimedRewardsSnapshotTimestamp != 0) {
            walletStakingState.unclaimedRewardsSnapshot = _calculateRewards(walletStakingState);
        }
        // solhint-disable-next-line not-rely-on-time
        walletStakingState.unclaimedRewardsSnapshotTimestamp = block.timestamp;
    }

    /// @dev Calculate the outstanding MDC reward token for a given wallet address
    /// @param wallet The staking wallet address
    /// @return The total amount of outstanding MDC reward token for the given wallet address
    function calculateRewards(address wallet) external view returns (uint256) {
        return _calculateRewards(walletStakingStates[wallet]);
    }

    /// @dev Internal function that calculates the outstanding MDC reward token
    /// @param walletStakingState The wallet staking state struct
    /// @return The total amount of outstanding MDC reward token
    function _calculateRewards(WalletStakingState memory walletStakingState) internal view returns (uint256) {
        if (walletStakingState.unclaimedRewardsSnapshotTimestamp != 0) {
            return
                walletStakingState.unclaimedRewardsSnapshot +
                walletStakingState.stakedFlorinTokens.mulDiv(
                    // solhint-disable-next-line not-rely-on-time
                    mdcPerFLRperSecond * (block.timestamp - walletStakingState.unclaimedRewardsSnapshotTimestamp),
                    10 ** 18,
                    MathUpgradeable.Rounding.Down
                );
        }
        return 0;
    }

    /// @dev A FLR staker can claim the outstanding amount of MDC reward token (only when not paused)
    /// @notice Emits event Claim
    function claim() external whenNotPaused {
        WalletStakingState storage walletStakingState = walletStakingStates[_msgSender()];
        _snapshotRewards(walletStakingState);
        uint256 unclaimedRewards = walletStakingState.unclaimedRewardsSnapshot;
        if (unclaimedRewards == 0) {
            revert Errors.UnclaimedRewardsMustBeGreaterThanZero();
        }
        walletStakingState.unclaimedRewardsSnapshot = 0;
        mediciToken.safeTransfer(_msgSender(), unclaimedRewards);
        emit Claim(_msgSender(), unclaimedRewards);
    }

    /// @dev Get the total amount of staked FLR token
    /// @return The total amount of staked FLR token
    function getTotalStakedFlorinTokens() public view returns (uint256) {
        return totalStakedFlorinTokens;
    }

    /// @dev Get the staking state for a given wallet
    /// @param wallet The wallet address
    /// @return The staking state struct of the given wallet address
    function getWalletStakingState(address wallet) external view returns (WalletStakingState memory) {
        return walletStakingStates[wallet];
    }

    /// @dev Get the maximum amount of assets (FLR token) that can be withdrawn for a given staking wallet address
    /// @param stakingWallet Address of the staking wallet
    /// @return Maximum amount of staked assets to withdraw
    function getMaxUnstake(address stakingWallet) external view returns (uint256) {
        return _convertToFlorinTokens(walletStakingStates[stakingWallet].stakedShares);
    }

    /// @dev Get the maximum amount of shares that can be redeemed for a given staking wallet
    /// @param stakingWallet Address of the staking wallet (staker)
    /// @return Maximum amount of shares to redeem
    function getStakedShares(address stakingWallet) external view returns (uint256) {
        return walletStakingStates[stakingWallet].stakedShares;
    }

    /// @dev Converts a given amount of assets (FLR Token) into the amount of shares
    /// @param florinTokens Amount of assets
    /// @return Amount of shares
    function _convertToShares(uint256 florinTokens) internal view returns (uint256) {
        uint256 totalShares_ = totalShares;
        return (florinTokens == 0 || totalShares_ == 0) ? florinTokens : florinTokens.mulDiv(totalShares_, getTotalStakedFlorinTokens(), MathUpgradeable.Rounding.Down);
    }

    /// @dev Converts a given amount of shares into the amount of assets (FLR Token)
    /// @param shares Amount of shares
    /// @return Amount of assets (FLR token)
    function _convertToFlorinTokens(uint256 shares) internal view returns (uint256) {
        uint256 totalShares_ = totalShares;
        return (totalShares_ == 0) ? shares : shares.mulDiv(getTotalStakedFlorinTokens(), totalShares_, MathUpgradeable.Rounding.Down);
    }
}

