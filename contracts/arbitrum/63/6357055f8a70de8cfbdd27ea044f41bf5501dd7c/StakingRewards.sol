// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./Math.sol";
import "./SafeMath.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";

import "./Initializable.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";

// Inheritance
import "./IStakingRewards.sol";
import "./RewardsDistributionRecipient.sol";
// logs
import "./console.sol";

// https://docs.synthetix.io/contracts/source/contracts/stakingrewards
abstract contract StakingRewards is
    IStakingRewards,
    RewardsDistributionRecipient,
    ReentrancyGuard,
    Pausable,
    Initializable
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========== CONSTANTS ========== */

    uint public constant PRECISION = 1e18;
    uint public constant PCT_BASE = 10000;
    uint public constant DAY = 86400;

    /* ========== STATE VARIABLES ========== */

    IERC20 public rewardsToken;
    IERC20 public stakingToken;

    mapping(address => uint256) public rewards;

    uint256 internal _totalSupply;
    mapping(address => uint256) internal _balances;

    struct Profits {
        uint digital;
        uint american;
        uint turbo;
    }
    
    struct PendingReward {
        address staker;
        uint reward;
    }

    address[] internal activeStakerList;
    mapping(address => uint256) internal activeStakers;

    Profits profits;

    /* ========== CONSTRUCTOR ========== */

    function _configure(
        address _rewardsDistribution,
        IERC20 _rewardsToken,
        IERC20 _stakingToken
    ) internal {
        rewardsToken = _rewardsToken;
        stakingToken = _stakingToken;
        rewardsDistribution = _rewardsDistribution;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */


    /* ========== PURE VIRTUAL FUNCTIONS ========== */

    /// @dev informs about platform reward
    function processPlatformReward(uint reward) virtual internal;

    function getUserPercents(address account)
        view virtual public
        returns (uint d);

    function calculateUserPayout(
        address account,
        uint userProfit
    ) public virtual view returns(uint payout);

    /* ========== MODIFIERS ========== */

    function _partOf(uint value, uint a, uint b)
        internal pure returns (uint)
    {
        return value * a / b;
    }

    function _splitAmount(uint amount) internal view
        returns(uint digital, uint amercan, uint turbo)
    {
        uint sum = profits.digital + profits.american + profits.turbo;
        require(amount < sum, "SC:INCORRECT_REWARD");

        digital = _partOf(profits.digital, amount, sum);
        amercan = _partOf(profits.american, amount, sum);
        turbo   = _partOf(profits.turbo, amount, sum);
    }

    function updateProfits(uint amount) internal
    {
        (uint d, uint a, uint t) = _splitAmount(amount);
        profits.digital  -= d;
        profits.american -= a;
        profits.turbo    -= t;
    }

    function getActiveStakerCount() public view returns (uint) {
        return activeStakerList.length;
    }

    function addStaker(address staker) internal returns (uint pos) {
        activeStakerList.push(staker);
        pos = activeStakerList.length - 1;
        activeStakers[staker] = pos;
    }

    function removeStaker(address staker) internal returns (uint pos) {
        pos = activeStakers[staker];
        address _staker = activeStakerList[pos];
        if (_staker == staker) {
            uint length = activeStakerList.length;
            if (length > 1) {
                address last = activeStakerList[length - 1];
                activeStakerList[pos] = last;
                activeStakers[last] = pos;
            }
            activeStakerList.pop(); 
            delete activeStakers[staker];
        }
    }

    function getActiveStakers(uint from, uint count) public view returns (address[] memory stakers)
    {
        uint length = activeStakerList.length;
        if (from < length) {
            uint available = length - from;
            if (count > available || count == 0) count = available;
            stakers= new address[](count);
            for (uint i = 0; i < count; i++) {
                stakers[i] = activeStakerList[i + from];
            }
        }
    }
    
    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event LossAdded(uint256 amount);
    event StakingLoss(address indexed account, uint256 amount);
    event Staked(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event RewardPaid(address indexed account, uint256 reward);
    event GainLossSettled(address indexed account, uint gain, uint loss);
}

