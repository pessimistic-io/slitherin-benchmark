pragma solidity 0.8.16;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./IMonolithVoter.sol";

import "./console.sol";

contract TokenBooster is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant WEEK = 1 weeks;

    IMonolithVoter public monolith;
    IERC20Upgradeable public token; // moSolid
    uint256 public startTime;

    uint256 public maxBoost;
    uint256 public weeksToMaxBoost;
    uint256 public boostPerWeek;

    // `weeklyTotalWeight` and `weeklyWeightOf` track the total boosted weight for each week,
    // week -> weight
    mapping(uint256 => uint256) public weeklyTotalWeight;
    // user -> week -> weight
    mapping(address => mapping(uint256 => uint256)) public weeklyWeightOf;

    // balance of staked token for each user
    // user -> index
    mapping(address => uint256) public tokenBalanceOf;
    uint256 public totalTokenBalance;

    // user -> week
    mapping(address => uint256) public userLastUpdatedWeek;

    event NewLock(address indexed user, uint256 amount, uint256 lockWeeks);
    event ExtendLock(
        address indexed user,
        uint256 amount,
        uint256 oldWeeks,
        uint256 newWeeks
    );
    event NewExitStream(
        address indexed user,
        uint256 startTime,
        uint256 amount
    );
    event ExitStreamWithdrawal(
        address indexed user,
        uint256 claimed,
        uint256 remaining
    );

    function initialize(
        uint256 _maxBoost, // e.g. 1.5e18 for 50%
        uint256 _weeksToMaxBoost, // e.g. 16
        uint256 _boostPerWeek // maxBoost ** (1 / weeksToMaxBoost) - 1
    ) public initializer {
        __Ownable_init();

        startTime = (block.timestamp / WEEK) * WEEK;

        maxBoost = _maxBoost;
        weeksToMaxBoost = _weeksToMaxBoost;
        boostPerWeek = _boostPerWeek;
    }

    function setAddresses(
        IERC20Upgradeable _token,
        IMonolithVoter _monolithVoter
    ) external onlyOwner {
        token = _token;
        monolith = _monolithVoter;
    }

    function getWeek() public view returns (uint256) {
        return (block.timestamp - startTime) / WEEK;
    }

    /**
        @notice Get the current lock weight for a user
     */
    function userWeight(address _user) external view returns (uint256) {
        return weeklyWeightOf[_user][getWeek()];
    }

    /**
        @notice Get the current total lock weight
     */
    function totalWeight() external view returns (uint256) {
        return weeklyTotalWeight[getWeek()];
    }

    /**
        @notice Get the user lock weight and total lock weight for the given week
     */
    function weeklyWeight(address _user, uint256 _week)
        external
        view
        returns (uint256, uint256)
    {
        return (weeklyWeightOf[_user][_week], weeklyTotalWeight[_week]);
    }

    function updateState(address user, uint256 iterations) public {
        uint256 week = getWeek();
        if (iterations == 0 || iterations > week) iterations = week;
        iterations += weeksToMaxBoost;

        uint256 lastUpdatedWeek = userLastUpdatedWeek[user];
        uint256 weight = weeklyWeightOf[user][lastUpdatedWeek];

        for (uint256 i = lastUpdatedWeek + 1; i < iterations; i++) {
            weeklyWeightOf[user][i] = weight;
        }

        userLastUpdatedWeek[user] = iterations - 1;
    }

    function _stake(
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (bool) {
        // get current week
        uint256 week = getWeek();

        updateState(_to, week);

        if (_from != address(this)) {
            // transfer token
            token.safeTransferFrom(msg.sender, address(this), _amount);
        }

        // update user token balance
        tokenBalanceOf[_to] += _amount;
        totalTokenBalance += _amount;

        // calculate user max boosted amount
        uint256 maxBoostedAmount = (tokenBalanceOf[_to] * maxBoost) / PRECISION;

        // add new amounts to user weights
        uint256 boostedAmount = _amount;
        for (uint256 i = week; i < week + weeksToMaxBoost; i++) {
            // check max boosted amount
            if (weeklyWeightOf[_to][i] + boostedAmount > maxBoostedAmount) {
                boostedAmount = maxBoostedAmount - weeklyWeightOf[_to][i];
            }

            // update user weight and carray previous amount (baseAmount)
            weeklyWeightOf[_to][i] += boostedAmount;

            // update total
            weeklyTotalWeight[i] += boostedAmount;

            // increase boostedAmount for next week
            boostedAmount += (boostedAmount * boostPerWeek) / PRECISION;
        }

        userLastUpdatedWeek[_to] = week + weeksToMaxBoost - 1;
    }

    function stake(address _to, uint256 _amount) external {
        _stake(msg.sender, _to, _amount);
        emit NewLock(_to, _amount, 0);
    }

    function unstake(uint256 _amount) external returns (bool) {
        require(
            _amount <= tokenBalanceOf[msg.sender],
            "Amount is more than user balance"
        );

        uint256 week = getWeek();

        require(
            monolith.userVotes(msg.sender, week) == 0,
            "Use has active vote"
        );

        // get current week weight
        uint256 weightBeforeUnstake = weeklyWeightOf[msg.sender][week];

        // reset users weights
        for (uint256 i = week; i < week + weeksToMaxBoost; i++) {
            weeklyTotalWeight[i] -= weeklyWeightOf[msg.sender][i];
            weeklyWeightOf[msg.sender][i] = 0;
        }

        uint256 remain = tokenBalanceOf[msg.sender] - _amount;
        // set user balance to 0 to avoid adding extra balance in _stake
        totalTokenBalance -= tokenBalanceOf[msg.sender];
        tokenBalanceOf[msg.sender] = 0;
        if (remain > 0) {
            // stake remaining amount
            _stake(address(this), msg.sender, remain);
        }

        // calculate seconds from start of the week
        uint256 passedSeconds = block.timestamp -
            (block.timestamp / WEEK) *
            WEEK;

        // calculate user weight from start of week until now
        weightBeforeUnstake = (weightBeforeUnstake * passedSeconds) / WEEK;

        // calculate user weight from now to the end of week
        uint256 weightAfterUnstake = (weeklyWeightOf[msg.sender][week] *
            (WEEK - passedSeconds)) / WEEK;

        // set current week weight and update total weight
        weeklyTotalWeight[week] -= weeklyWeightOf[msg.sender][week];
        weeklyWeightOf[msg.sender][week] =
            weightBeforeUnstake +
            weightAfterUnstake;
        weeklyTotalWeight[week] += weeklyWeightOf[msg.sender][week];
    }
}

