//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StakingRulesBase.sol";

contract ERC721StakingRules is StakingRulesBase {
    uint256 public staked;
    uint256 public maxStakeableTotal;
    uint256 public maxWeight;
    uint256 public boostFactor;
    uint256 public weightPerToken;
    uint256 public boostPerToken;

    /// @dev maps user wallet to current staked weight. For weight values, see getWeight
    mapping (address => uint256) public weightStaked;

    bool public paused;

    event MaxWeight(uint256 maxWeight);
    event MaxStakeableTotal(uint256 maxStakeableTotal);
    event WeightPerToken(uint256 weightPerToken);
    event BoostFactor(uint256 boostFactor);
    event BoostPerToken(uint256 boostPerToken);
    event Pause();
    event Unpause();

    error MaxWeightReached();
    error Paused();
    error Unpaused();

    function init(
        address _admin,
        address _harvesterFactory,
        uint256 _maxWeight,
        uint256 _maxStakeableTotal,
        uint256 _weightPerToken,
        uint256 _boostFactor,
        uint256 _boostPerToken
    ) external initializer {
        _initStakingRulesBase(_admin, _harvesterFactory);

        _setMaxWeight(_maxWeight);
        _setMaxStakeableTotal(_maxStakeableTotal);
        _setWeightPerToken(_weightPerToken);
        _setBoostFactor(_boostFactor);
        _setBoostPerToken(_boostPerToken);
    }

    /// @inheritdoc IStakingRules
    function getUserBoost(address, address, uint256, uint256) external view override returns (uint256) {
        return boostPerToken;
    }

    /// @inheritdoc IStakingRules
    function getHarvesterBoost() external view returns (uint256) {
        // quadratic function in the interval: [1, (1 + boost_factor)] based on number of parts staked.
        // exhibits diminishing returns on boosts as more legions are added
        // num: number of entities staked on harvester
        // max: number of entities where you achieve max boost
        // avg_legion_rank: avg legion rank on your harvester
        // boost_factor: the amount of boost you want to apply to parts
        // default is 1 = 50% boost (1.5x) if num = max

        uint256 n = (staked > maxStakeableTotal ? maxStakeableTotal : staked) * Constant.ONE;
        uint256 maxEntities = maxStakeableTotal * Constant.ONE;
        if (maxEntities == 0) {
            return Constant.ONE;
        }

        return Constant.ONE + (2 * n - n ** 2 / maxEntities) * boostFactor / maxEntities;
    }

    function getWeight(uint256) public view returns (uint256) {
        return weightPerToken;
    }

    function _processStake(address _user, address, uint256 _tokenId, uint256) internal override {
        if (paused) revert Paused();

        staked++;
        weightStaked[_user] += getWeight(_tokenId);

        if (weightStaked[_user] > maxWeight) revert MaxWeightReached();
    }

    function _processUnstake(address _user, address, uint256 _tokenId, uint256) internal override {
        if (paused) revert Paused();

        staked--;
        weightStaked[_user] -= getWeight(_tokenId);
    }

    // ADMIN

    function setMaxWeight(uint256 _maxWeight) external onlyRole(SR_ADMIN) {
        _setMaxWeight(_maxWeight);
    }

    function setMaxStakeableTotal(uint256 _maxStakeableTotal) external onlyRole(SR_ADMIN) {
        _setMaxStakeableTotal(_maxStakeableTotal);
    }

    function setBoostFactor(uint256 _boostFactor) external onlyRole(SR_ADMIN) {
        nftHandler.harvester().callUpdateRewards();

        _setBoostFactor(_boostFactor);
    }

    function pause() external onlyRole(SR_ADMIN) {
        if (paused) revert Paused();

        paused = true;

        emit Pause();
    }

    function unpause() external onlyRole(SR_ADMIN) {
        if (!paused) revert Unpaused();

        paused = false;

        emit Unpause();
    }

    function _setMaxWeight(uint256 _maxWeight) internal {
        maxWeight = _maxWeight;
        emit MaxWeight(_maxWeight);
    }

    function _setMaxStakeableTotal(uint256 _maxStakeableTotal) internal {
        maxStakeableTotal = _maxStakeableTotal;
        emit MaxStakeableTotal(_maxStakeableTotal);
    }

    function _setWeightPerToken(uint256 _weightPerToken) internal {
        weightPerToken = _weightPerToken;
        emit WeightPerToken(_weightPerToken);
    }

    function _setBoostFactor(uint256 _boostFactor) internal {
        boostFactor = _boostFactor;
        emit BoostFactor(_boostFactor);
    }

    function _setBoostPerToken(uint256 _boostPerToken) internal {
        boostPerToken = _boostPerToken;
        emit BoostPerToken(_boostPerToken);
    }
}
