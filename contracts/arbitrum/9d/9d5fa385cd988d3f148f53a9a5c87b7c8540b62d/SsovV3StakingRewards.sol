// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

// Interfaces
import {IERC20 as OZERC20} from "./interfaces_IERC20.sol";
import {ISsovV3} from "./ISsovV3.sol";

// Libraries
import {Math} from "./Math.sol";
import {SafeERC20} from "./SafeERC20.sol";

// Contracts
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Pausable} from "./Pausable.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";
import {AccessControl} from "./AccessControl.sol";

/***
 * Deposit SSOV V3 deposit positions (ERC721) to earn rewards.
 * Rewards earned are based on strike of the position.
 */

interface IERC20 is OZERC20 {
    function decimals() external view returns (uint256);
}

contract SsovV3StakingRewards is
    AccessControl,
    ContractWhitelist,
    Pausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    bytes32 public constant MANAGER_ROLE =
        keccak256(abi.encodePacked("MANAGER_ROLE"));

    struct RewardInfo {
        uint256 rewardAmount;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 rewardRateStored;
        uint256 lastUpdateTime;
        uint256 totalSupply;
        uint256 decimalsPrecision;
        IERC20 rewardToken;
    }

    struct StakedPosition {
        uint256[] rewardRateStored;
        uint256[] rewardsPaid;
        uint256 stakeAmount;
        bool staked;
    }

    /**
     * @notice Staked positions of users.
     * @dev    hash(ssov, positionId, epoch) => SsovUserPosition
     */
    mapping(bytes32 => StakedPosition) private stakedPositions;

    /**
     * @notice Rewards related data for each ssov
     * @dev    hash(ssov, strike, epoch) => RewardInfo
     */
    mapping(bytes32 => RewardInfo[]) private ssovRewardStrikeInfo;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);
    }

    /* ========== PUBLIC METHODS ========== */

    /// @notice      Allows to stake the staking token into the contract for rewards
    /// @param _ssov Address of the SSOV of the deposit position
    /// @param _id   ID of the deposit position
    function stake(
        address _ssov,
        uint _id
    ) external whenNotPaused nonReentrant {
        _isEligibleSender();

        ISsovV3 ssov = ISsovV3(_ssov);

        if (ssov.ownerOf(_id) != msg.sender) revert NotOwnerOfWritePosition();

        uint256 currentEpoch = ssov.currentEpoch();

        (uint256 epoch, uint256 strike, uint256 amount, , ) = ssov
            .writePosition(_id);

        if (epoch != currentEpoch) revert NotCurrentEpoch();

        if (ssov.getEpochData(epoch).expiry <= block.timestamp) {
            revert SsovEpochExpired();
        }

        bytes32 _positionId = getId(_ssov, _id, epoch);
        bytes32 _rewardInfoId = getId(_ssov, strike, epoch);

        if (stakedPositions[_positionId].staked) {
            revert SsovPositionAlreadyStaked();
        }

        _updateUserPositionAndRewards(_rewardInfoId, _positionId, amount);

        emit SsovPositionStaked(_ssov, _id, amount);
    }

    /**
     * @notice          Claim rewards of a staked position.
     * @param _ssov     Address of the ssov vault
     * @param _id       ID of the write position.
     * @param _receiver Address of the reward tokens receiver.
     */
    function claim(
        address _ssov,
        uint256 _id,
        address _receiver
    ) external whenNotPaused nonReentrant {
        _isEligibleSender();
        _claim(_id, _ssov, _receiver);
    }

    /**
     * @notice             Claim rewards for multiple staked positions.
     * @param _positionIds IDs of the write positions staked.
     * @param _ssov        Address of the SSOV.
     * @param _receiver    Address of the receiver.
     */
    function multiClaim(
        uint256[] calldata _positionIds,
        address _ssov,
        address _receiver
    ) external whenNotPaused nonReentrant {
        for (uint256 i; i < _positionIds.length; ) {
            _claim(_positionIds[i], _ssov, _receiver);
            unchecked {
                ++i;
            }
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice             Returns information about rewards.
     * @param id           ID from ssovRewardStrikeInfo mapping.
     * @return _rewardInfo Information about the rewards.
     */
    function getSsovEpochStrikeRewardsInfo(
        bytes32 id
    ) public view returns (RewardInfo[] memory _rewardInfo) {
        _rewardInfo = new RewardInfo[](ssovRewardStrikeInfo[id].length);
        _rewardInfo = ssovRewardStrikeInfo[id];
        return _rewardInfo;
    }

    /**
     * @notice             Returns information about rewards.
     * @param  _ssov       Address of the ssov.
     * @param  _strike     Strike of the ssov.
     * @param  _epoch      Epoch of the ssov.
     * @return _rewardInfo Information about the rewards.
     */
    function getSsovEpochStrikeRewardsInfo(
        address _ssov,
        uint256 _strike,
        uint256 _epoch
    ) external view returns (RewardInfo[] memory _rewardInfo) {
        bytes32 rewardsInfoId = getId(_ssov, _strike, _epoch);
        return getSsovEpochStrikeRewardsInfo(rewardsInfoId);
    }

    /**
     *
     * @notice                 Get user staked position information.
     * @param id               ID of the staked position from stakedPositions mapping.
     * @return _stakedPosition Information about the staked position.
     */
    function getUserStakedPosition(
        bytes32 id
    ) external view returns (StakedPosition memory _stakedPosition) {
        _stakedPosition = stakedPositions[id];
    }

    /**
     * @param _ssov  Address of the SSOV
     * @param _uint1 Strike | ssov position ID
     * @param _uint2 Epoch
     */
    function getId(
        address _ssov,
        uint256 _uint1,
        uint256 _uint2
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_ssov, _uint1, _uint2));
    }

    /**
     * @notice               Get rewards earned by a write position.
     * @param  _ssov         Address of the ssov.
     * @return rewardTokens  Array of reward tokens.
     * @return rewardAmounts Array of reward amounts.
     */
    function earned(
        address _ssov,
        uint256 _positionId
    )
        external
        view
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        (uint epoch, uint256 strike, , , ) = ISsovV3(_ssov).writePosition(
            _positionId
        );

        bytes32 stakedPositionId = getId(_ssov, _positionId, epoch);
        if (stakedPositions[stakedPositionId].staked) {
            bytes32 rewardsInfoId = getId(_ssov, strike, epoch);
            uint256 len = ssovRewardStrikeInfo[rewardsInfoId].length;

            rewardTokens = new address[](len);
            rewardAmounts = new uint256[](len);

            IERC20 rewardToken;
            uint256 rewardAmount;
            for (uint256 i; i < len; ) {
                (, rewardAmount, , rewardToken) = earned(
                    rewardsInfoId,
                    stakedPositionId,
                    i
                );

                rewardTokens[i] = address(rewardToken);
                rewardAmounts[i] = rewardAmount;

                unchecked {
                    ++i;
                }
            }
        }
    }

    /**
     * @notice                    Get Amount of rewards and reward tokens earned.
     * @return rewardRate         New rate of reward distribution.
     * @return earnedRewards      Amount of earned reward tokens.
     * @return lastApplicableTime Last applicable time updated.
     * @return rewardToken        Address of the reward token.
     */
    function earned(
        bytes32 _rewardsInfoId,
        bytes32 _positionId,
        uint256 _index
    )
        public
        view
        returns (
            uint256 rewardRate,
            uint256 earnedRewards,
            uint256 lastApplicableTime,
            IERC20 rewardToken
        )
    {
        StakedPosition memory _stakedPosition = stakedPositions[_positionId];

        RewardInfo memory _rewardInfo = ssovRewardStrikeInfo[_rewardsInfoId][
            _index
        ];

        uint256 rewardsCollected = _getRewardsCollected(_rewardInfo);

        rewardRate =
            (rewardsCollected * _rewardInfo.decimalsPrecision) /
            _rewardInfo.totalSupply;

        rewardRate = _rewardInfo.rewardRateStored + rewardRate;

        earnedRewards =
            ((
                ((rewardRate - _stakedPosition.rewardRateStored[_index]) *
                    _stakedPosition.stakeAmount)
            ) / _rewardInfo.decimalsPrecision) -
            _stakedPosition.rewardsPaid[_index];

        rewardToken = _rewardInfo.rewardToken;

        lastApplicableTime = Math.min(
            _rewardInfo.periodFinish,
            block.timestamp
        );
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice              Add rewards for an ssov for given strike and current epoch.
     * @param _ssov         Address of the ssov.
     * @param _strike       Strike to set rewards for.
     * @param _rewardToken  Address of the reward token.
     * @param _rewardAmount Amount of reward token to set.
     */
    function addRewards(
        address _ssov,
        uint256 _strike,
        address _rewardToken,
        uint256 _rewardAmount
    ) public onlyRole(MANAGER_ROLE) {
        if (_rewardToken == address(0)) {
            revert ZeroAddress();
        }
        ISsovV3 ssov = ISsovV3(_ssov);
        IERC20 rewardToken = IERC20(_rewardToken);
        uint256 epoch = ssov.currentEpoch();
        bytes32 id = getId(_ssov, _strike, epoch);

        RewardInfo memory _rewardInfo;

        _rewardInfo.periodFinish = ssov.getEpochData(epoch).expiry;

        if (_rewardInfo.periodFinish <= block.timestamp) {
            revert SsovEpochExpired();
        }

        _rewardInfo.rewardAmount = _rewardAmount;
        _rewardInfo.rewardToken = rewardToken;
        _rewardInfo.lastUpdateTime = block.timestamp;
        _rewardInfo.rewardRate =
            _rewardAmount /
            (_rewardInfo.periodFinish - block.timestamp);
        _rewardInfo.decimalsPrecision =
            10 ** _rewardInfo.rewardToken.decimals();

        ssovRewardStrikeInfo[id].push(_rewardInfo);

        rewardToken.safeTransferFrom(msg.sender, address(this), _rewardAmount);

        emit SsovStrikeRewardsSet(_ssov, _strike, epoch, _rewardInfo);
    }

    /**
     * @notice              Add rewards for multiple strikes of an ssov.
     * @param _ssov         Address of the ssov.
     * @param _strikes      Strikes to set rewards for.
     * @param _rewardToken  Address of the reward token.
     * @param _rewardAmount Amount of reward token to set.
     */
    function addSingleRewardsForMultipleStrikes(
        address _ssov,
        uint256[] calldata _strikes,
        address _rewardToken,
        uint256 _rewardAmount
    ) external onlyRole(MANAGER_ROLE) {
        for (uint256 i; i < _strikes.length; ) {
            addRewards(_ssov, _strikes[i], _rewardToken, _rewardAmount);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice               Add rewards of multiple amounts for multiple
     *                       strikes of an ssov.
     * @param _ssov          Address of the ssov.
     * @param _strikes       Strikes to set rewards for.
     * @param _rewardToken   Address of the reward token.
     * @param _rewardAmounts Amounts of reward token to set.
     */
    function addMultipleRewardsForMultipleStrikes(
        address _ssov,
        uint256[] calldata _strikes,
        address _rewardToken,
        uint256[] calldata _rewardAmounts
    ) external onlyRole(MANAGER_ROLE) {
        for (uint256 i; i < _strikes.length; ) {
            addRewards(_ssov, _strikes[i], _rewardToken, _rewardAmounts[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice               Transfers all funds to msg.sender
    /// @dev                  Can only be called by the owner
    /// @param tokens         The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    function emergencyWithdraw(
        address[] calldata tokens,
        bool transferNative
    ) external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        IERC20 token;

        for (uint256 i = 0; i < tokens.length; i++) {
            token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
        }

        emit EmergencyWithdraw(msg.sender);

        return true;
    }

    /// @notice          Adds to the contract whitelist
    /// @dev             Can only be called by the owner
    /// @param _contract the contract to be added to the whitelist
    function addToContractWhitelist(
        address _contract
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addToContractWhitelist(_contract);
    }

    /// @notice          Removes from the contract whitelist
    /// @dev             Can only be called by the owner
    /// @param _contract the contract to be removed from the whitelist
    function removeFromContractWhitelist(
        address _contract
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeFromContractWhitelist(_contract);
    }

    /// @notice Pauses the contract
    /// @dev    Can only be called by the owner
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    /// @dev    Can only be called by the owner
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _claim(uint256 _id, address _ssov, address _receiver) private {
        if (_receiver == address(0)) {
            revert ZeroAddress();
        }

        (uint epoch, uint256 strike, , , ) = ISsovV3(_ssov).writePosition(_id);

        bytes32 positionId = getId(_ssov, _id, epoch);
        bytes32 rewardsInfoId = getId(_ssov, strike, epoch);

        if (!stakedPositions[positionId].staked) {
            revert NotStaked();
        }

        if (ISsovV3(_ssov).ownerOf(_id) != msg.sender) {
            revert NotOwnerOfWritePosition();
        }

        uint256 len = ssovRewardStrikeInfo[rewardsInfoId].length;

        if (len == 0) {
            revert RewardsNotSet();
        }

        uint256 rewardRate;
        uint256 earnedRewards;
        uint256 lastApplicableTime;
        IERC20 rewardToken;

        for (uint256 i; i < len; ) {
            (
                rewardRate,
                earnedRewards,
                lastApplicableTime,
                rewardToken
            ) = earned(rewardsInfoId, positionId, i);

            ssovRewardStrikeInfo[rewardsInfoId][i]
                .rewardRateStored = rewardRate;

            ssovRewardStrikeInfo[rewardsInfoId][i]
                .lastUpdateTime = lastApplicableTime;

            stakedPositions[positionId].rewardsPaid[i] += earnedRewards;

            rewardToken.safeTransfer(_receiver, earnedRewards);

            emit Claimed(earnedRewards, _id, _ssov, address(rewardToken));

            unchecked {
                ++i;
            }
        }

        if (ISsovV3(_ssov).getEpochData(epoch).expiry <= block.timestamp) {
            delete stakedPositions[positionId];
        }
    }

    function _updateUserPositionAndRewards(
        bytes32 _rewardsInfoId,
        bytes32 _positionId,
        uint256 _amount
    ) private {
        uint256 len = ssovRewardStrikeInfo[_rewardsInfoId].length;
        if (len == 0) {
            revert RewardsNotSet();
        }

        StakedPosition memory _stakedPosition;
        RewardInfo memory _rewardInfo;

        uint256 rewardsCollected;

        _stakedPosition.staked = true;
        _stakedPosition.rewardRateStored = new uint256[](len);
        _stakedPosition.rewardsPaid = new uint256[](len);
        _stakedPosition.stakeAmount = _amount;

        uint256 rewardRate;

        for (uint256 i; i < len; ) {
            _rewardInfo = ssovRewardStrikeInfo[_rewardsInfoId][i];

            rewardsCollected = _getRewardsCollected(_rewardInfo);

            if (_rewardInfo.totalSupply != 0) {
                rewardRate =
                    (rewardsCollected * _rewardInfo.decimalsPrecision) /
                    _rewardInfo.totalSupply;

                _stakedPosition.rewardRateStored[i] =
                    rewardRate +
                    _rewardInfo.rewardRateStored;

                _rewardInfo.rewardRateStored = _stakedPosition.rewardRateStored[
                    i
                ];

                _rewardInfo.lastUpdateTime = Math.min(
                    block.timestamp,
                    _rewardInfo.periodFinish
                );
            }

            _rewardInfo.totalSupply += _amount;
            ssovRewardStrikeInfo[_rewardsInfoId][i] = _rewardInfo;

            unchecked {
                ++i;
            }
        }

        stakedPositions[_positionId] = _stakedPosition;
    }

    function _getRewardsCollected(
        RewardInfo memory _rewardInfo
    ) private view returns (uint256 rewardsCollected) {
        rewardsCollected =
            _rewardInfo.rewardRate *
            (Math.min(_rewardInfo.periodFinish, block.timestamp) -
                _rewardInfo.lastUpdateTime);
    }

    /* ========== EVENTS ========== */

    event SsovStrikeRewardsSet(
        address ssov,
        uint256 strike,
        uint256 epoch,
        RewardInfo rewardInfo
    );
    event SsovPositionStaked(address ssov, uint256 id, uint256 amount);
    event EmergencyWithdraw(address sender);
    event Staked(
        address indexed user,
        uint256 positionId,
        address ssov,
        uint256 strike,
        uint256 amount
    );
    event Claimed(
        uint256 rewardAmount,
        uint256 positionId,
        address ssov,
        address rewardToken
    );

    /* ========== ERRORS ========== */

    error SsovPositionAlreadyStaked();
    error NotOwnerOfWritePosition();
    error NotCurrentEpoch();
    error InvalidArrayLengths();
    error SsovEpochExpired();
    error RewardsNotSet();
    error NotStaked();
    error FullRewardsClaimed();
    error RewardsAlreadySet();
    error ZeroAddress();
}

