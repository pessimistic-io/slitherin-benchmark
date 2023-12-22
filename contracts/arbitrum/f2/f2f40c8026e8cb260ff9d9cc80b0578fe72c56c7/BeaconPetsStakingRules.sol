//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StakingRulesBase.sol";

interface IBeacon {
    function getYieldBoost(uint256 _tokenId) external view returns(uint256);
}

interface IBeaconPetsStakingRules {
    function setYieldBoostToUserDepositBoost(uint256 _yieldBoost, uint256 _userDepositBoost) external;
}

contract BeaconPetsStakingRules is StakingRulesBase {
    uint256 public staked;

    uint256 public boostFactor;
    uint256 public boostPerToken;

    uint256 public maxStakeableTotal;
    uint256 public maxStakeablePerUser;

    address public beaconAddress;

    mapping(address => uint256) public beaconPetsAmountStaked;
    mapping(uint256 => uint256) public yieldBoostToUserDepositBoost;

    bool public paused;

    event BoostFactor(uint256 boostFactor);
    event BeaconAddress(address beaconAddress);
    event BoostPerToken(uint256 boostPerToken);
    event MaxStakeableTotal(uint256 maxStakeableTotal);
    event MaxStakeablePerUser(uint256 maxStakeablePerUser);

    event Pause();
    event Unpause();


    error MaxStakeablePerUserReached();
    error Paused();
    error Unpaused();

    function init(
        address _admin,
        address _harvesterFactory,
        address _beaconAddress,
        uint256 _maxStakeableTotal,
        uint256 _maxStakeablePerUser,
        uint256 _beaconPetsBoostFactor
    ) external initializer {
        _initStakingRulesBase(_admin, _harvesterFactory);

        _setBeaconAddress(_beaconAddress);

        _setMaxStakeableTotal(_maxStakeableTotal);
        _setMaxStakeablePerUser(_maxStakeablePerUser);
        _setBoostFactor(_beaconPetsBoostFactor);

        yieldBoostToUserDepositBoost[100000] = 0.2 * 10 ** 18;
        yieldBoostToUserDepositBoost[133333] = 0.25 * 10 ** 18;
        yieldBoostToUserDepositBoost[166667] = 0.3 * 10 ** 18;
        yieldBoostToUserDepositBoost[200000] = 0.35 * 10 ** 18;
    }

    /// @inheritdoc IStakingRules
    function getUserBoost(address, address, uint256 _tokenId, uint256) external view override returns (uint256) {
        uint256 _yieldBoost = IBeacon(beaconAddress).getYieldBoost(_tokenId);

        return yieldBoostToUserDepositBoost[_yieldBoost];
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

    function _processStake(address _user, address, uint256 _tokenId, uint256) internal override {
        if (paused) revert Paused();

        require(_tokenId < 4097, "Not a pet id!");

        if (beaconPetsAmountStaked[_user] + 1 > maxStakeablePerUser) revert MaxStakeablePerUserReached();

        beaconPetsAmountStaked[_user]++;
        staked++;
    }

    function _processUnstake(address _user, address, uint256 _tokenId, uint256) internal override {
        if (paused) revert Paused();

        require(_tokenId < 4097, "Not a pet id!");

        beaconPetsAmountStaked[_user]--;
        staked--;
    }

    // ADMIN
    function setMaxStakeableTotal(uint256 _maxStakeableTotal) external onlyRole(SR_ADMIN) {
        _setMaxStakeableTotal(_maxStakeableTotal);
    }

    function setMaxStakeablePerUser(uint256 _maxStakeablePerUser) external onlyRole(SR_ADMIN) {
        _setMaxStakeablePerUser(_maxStakeablePerUser);
    }

    function setBeaconAddress(address _beaconAddress) external onlyRole(SR_ADMIN) {
        _setBeaconAddress(_beaconAddress);
    }


    function setBoostFactor(uint256 _boostFactor) external onlyRole(SR_ADMIN) {
        nftHandler.harvester().callUpdateRewards();

        _setBoostFactor(_boostFactor);
    }

    function setYieldBoostToUserDepositBoost(uint256 _yieldBoost, uint256 _userDepositBoost) external {
        require(hasRole(SR_ADMIN, msg.sender) || msg.sender == address(nftHandler), "Bad permission");

        yieldBoostToUserDepositBoost[_yieldBoost] = _userDepositBoost;
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

    function _setBeaconAddress(address _beaconAddress) internal {
        beaconAddress = _beaconAddress;
        emit BeaconAddress(_beaconAddress);
    }

    function _setMaxStakeableTotal(uint256 _maxStakeableTotal) internal {
        maxStakeableTotal = _maxStakeableTotal;
        emit MaxStakeableTotal(_maxStakeableTotal);
    }

    function _setMaxStakeablePerUser(uint256 _maxStakeablePerUser) internal {
        maxStakeablePerUser = _maxStakeablePerUser;
        emit MaxStakeablePerUser(_maxStakeablePerUser);
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
