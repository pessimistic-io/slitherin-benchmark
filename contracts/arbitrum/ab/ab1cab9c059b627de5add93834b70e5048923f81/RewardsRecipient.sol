// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./SafeERC20Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./RoleCheckable.sol";
import "./IERC20.sol";
import "./IRewardsRecipient.sol";

/**
 * @title Rewards future abstraction
 * @notice Handles all future mechanisms along with reward-specific functionality
 * @dev Allows for better decoupling of rewards logic with core future logic
 */
abstract contract RewardsRecipient is
    RoleCheckable,
    ReentrancyGuardUpgradeable,
    IRewardsRecipient
{
    using SafeERC20Upgradeable for IERC20;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /* Rewards mecanisms */
    EnumerableSetUpgradeable.AddressSet internal rewardTokens;

    /* External contracts */
    address internal rewardsRecipient;

    /* Public */

    /**
     * @notice Harvest all rewards from the vault
     */
    function harvestRewards()
        public
        virtual
        override
        nonReentrant
        onlyController
    {
        _harvestRewards();
        emit RewardsHarvested();
    }

    /**
     * @notice Should be overridden and implemented by the future depending on platform-specific details
     */
    function _harvestRewards() internal virtual {}

    /**
     * @notice Transfer all the redeemable rewards to set defined recipient
     */
    function redeemAllVaultRewards() external virtual override onlyController {
        _redeemAllRewards();
    }

    /**
     * @notice Transfer the specified token reward balance tot the defined recipient
     * @param _rewardToken the reward token to redeem the balance of
     */
    function redeemVaultRewards(address _rewardToken)
        external
        virtual
        override
        onlyController
    {
        _redeemRewards(_rewardToken);
    }

    /**
     * @notice Transfer all the redeemable rewards to set defined recipient
     */
    function redeemAllWalletRewards() external virtual override onlyController {
        _redeemAllRewards();
    }

    /**
     * @notice Transfer the specified token reward balance tot the defined recipient
     * @param _rewardToken the reward token to redeem the balance of
     */
    function redeemWalletRewards(address _rewardToken)
        external
        virtual
        override
        onlyController
    {
        _redeemRewards(_rewardToken);
    }

    function _redeemAllRewards() internal {
        require(
            rewardsRecipient != address(0),
            "RewardsRecipient: ERR_RECIPIENT"
        );
        uint256 numberOfRewardTokens = rewardTokens.length();
        for (uint256 i; i < numberOfRewardTokens; i++) {
            IERC20 rewardToken = IERC20(rewardTokens.at(i));
            uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
            rewardToken.safeTransfer(rewardsRecipient, rewardTokenBalance);
            emit RewardTokenRedeemed(address(rewardToken), rewardTokenBalance);
        }
    }

    function _redeemRewards(address _rewardToken) internal {
        require(
            rewardsRecipient != address(0),
            "RewardsRecipient: ERR_RECIPIENT"
        );
        require(
            rewardTokens.contains(address(_rewardToken)),
            "RewardsRecipient: ERR_TOKEN_ADDRESS"
        );
        IERC20 rewardToken = IERC20(_rewardToken);
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        rewardToken.safeTransfer(rewardsRecipient, rewardTokenBalance);
        emit RewardTokenRedeemed(_rewardToken, rewardTokenBalance);
    }

    /**
     * @notice Add a token to the list of reward tokens
     * @param _token the reward token to add to the list
     * @dev the token must be different than the ibt
     */
    function addRewardsToken(address _token) external override onlyAdmin {
        require(
            _token != getIBTAddress(),
            "RewardsRecipient: ERR_TOKEN_ADDRESS"
        );
        rewardTokens.add(_token);
        emit RewardTokenAdded(_token);
    }

    /**
     * @notice Setter for the address of the rewards recipient
     */
    function setRewardRecipient(address _recipient)
        external
        override
        onlyAdmin
    {
        rewardsRecipient = _recipient;
        emit RewardsRecipientUpdated(_recipient);
    }

    /**
     * @notice Getter to check if a token is in the reward tokens list
     * @param _token the token to check if it is in the list
     * @return true if the token is a reward token
     */
    function isRewardToken(address _token)
        external
        view
        override
        returns (bool)
    {
        return rewardTokens.contains(address(_token));
    }

    /**
     * @notice Getter for the reward token at an index
     * @param _index the index of the reward token in the list
     * @return the address of the token at this index
     */
    function getRewardTokenAt(uint256 _index)
        external
        view
        override
        returns (address)
    {
        return rewardTokens.at(_index);
    }

    /**
     * @notice Getter for the size of the list of reward tokens
     * @return the number of token in the list
     */
    function getRewardTokensCount() external view override returns (uint256) {
        return rewardTokens.length();
    }

    /**
     * @notice Getter for the address of the rewards recipient
     * @return the address of the rewards recipient
     */
    function getRewardsRecipient() external view override returns (address) {
        return rewardsRecipient;
    }

    /**
     * @notice getter for the address of the IBT corresponding to this future
     * @return the address of the IBT
     */
    function getIBTAddress() public view virtual returns (address);
}

