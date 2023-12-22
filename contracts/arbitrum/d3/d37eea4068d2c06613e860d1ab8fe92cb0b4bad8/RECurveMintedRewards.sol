// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./IRECurveMintedRewards.sol";
import "./UpgradeableBase.sol";
import "./Roles.sol";

/**
    This works with curve gauges

    We set a reward rate

    Occasionally, we call "sendRewards", which calculates how much to add to the curve gauge

    The gauge will distribute rewards for the following 7 days
 */
contract RECurveMintedRewards is UpgradeableBase(3), IRECurveMintedRewards
{
    bytes32 constant RewardManagerRole = keccak256("ROLE:RECurveMintedRewards:rewardManager");

    uint256 public perDay;
    uint256 public perDayPerDollar;
    uint256 public lastRewardTimestamp;

    //------------------ end of storage

    bool public constant isRECurveMintedRewards = true;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ICanMint public immutable rewardToken;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ICurveGauge public immutable gauge;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ICurveStableSwap immutable pool;
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(ICanMint _rewardToken, ICurveGauge _gauge)
    {
        rewardToken = _rewardToken;
        gauge = _gauge;
        pool = gauge.lp_token();
    }

    function initialize()
        public
    {
        rewardToken.approve(address(gauge), type(uint256).max);
    }

    function checkUpgradeBase(address newImplementation)
        internal
        override
        view
    {
        assert(IRECurveMintedRewards(newImplementation).isRECurveMintedRewards());
    }
    
    function isRewardManager(address user) public view returns (bool) { return Roles.hasRole(RewardManagerRole, user); }

    modifier onlyRewardManager()
    {
        if (!isRewardManager(msg.sender) && msg.sender != owner()) { revert NotRewardManager(); }
        _;
    }

    function getCurveDollars()
        private
        view
        returns (uint256)
    {
        return pool.get_virtual_price() * gauge.totalSupply() / (1 ether * 1 ether);
    }

    function sendRewards(uint256 maxDollars)
        public
        onlyRewardManager
    {
        uint256 interval = block.timestamp - lastRewardTimestamp;
        if (interval == 0) { return; }
        uint256 dollars = getCurveDollars();
        if (dollars > maxDollars) { revert MaxDollarsExceeded(); }
        if (maxDollars > 1000000000000 || (maxDollars > 1000 && maxDollars > dollars * 2)) { revert MaxDollarsTooHigh(); }
        lastRewardTimestamp = block.timestamp;
        
        uint256 amount = interval * (dollars * perDayPerDollar + perDay) / 86400;
        if (amount > 0)
        {
            rewardToken.mint(address(this), amount);
            gauge.deposit_reward_token(address(rewardToken), amount);
        }
    }

    function sendAndSetRewardRate(uint256 _perDay, uint256 _perDayPerDollar, uint256 maxDollars)
        public
        onlyRewardManager
    {
        sendRewards(maxDollars);
        perDay = _perDay;
        perDayPerDollar = _perDayPerDollar;
        emit RewardRate(_perDay, _perDayPerDollar);
    }
    
    function setRewardManager(address manager, bool enabled) 
        public
        onlyOwner
    {
        Roles.setRole(RewardManagerRole, manager, enabled);
    }
}
