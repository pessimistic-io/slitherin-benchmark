// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable.sol";
import "./ERC20.sol";
import "./Math.sol";

import "./Constants.sol";
import "./BarqAwardsV0.sol";

/**
 * Counts points (claims to the barq token) awarded to the users while making
 * the transactions. The points map 1:1 to the actual barq tokens.
 */
contract BarqAwards is BarqAwardsV0 {
    /**
     * Emitted when daily limit of the award points has been reached for the
     * specified user.
     */
    event DailyAwardPointsLimitReached(address user);

    /**
     * Emitted when the daily maximum of awarded user transactions is changed.
     */
    event MaximumAwardedUserTransactionsPerDayChanged(uint256 value);

    /**
     * Emitted when a new awards presenter has been elected by the owner.
     */
    event PresenterChanged(address presenter);

    /**
     * Emitted when total limit of the award points has been reached.
     */
    event TotalAwardPointsLimitReached();

    /**
     * Stores total amount of points awarded thus far.
     */
    uint256 awardedPointsCount;

    /**
     * Stores total amount of points per user.
     */
    mapping(address => uint256) private awardedPoints;

    /**
     * Maps the number (index) of a day to addresses of all users that were
     * awarded points during that day. The mapping is regularly cleared from
     * old entries.
     */
    mapping(uint256 => mapping(address => uint256)) private dailyAwardedPoints;

    /**
     * Stores the number (index) of the day when at least one user was awarded
     * points.
     */
    uint256 private lastAwardDay;

    /**
     * Lists all users that were awarded points during the last day.
     */
    address[] private lastAwardedUsersList;

    /**
     * Owner-adjustable maximum number of user transactions per day.
     */
    uint256 private maximumUserTransactionsPerDay;

    /**
     * Address of the contract that is allowed to give out the award points.
     */
    address private presenterContract;

    /**
     * The amount of points that is awarded per single transaction.
     */
    uint256 public constant POINTS_PER_AWARD = 1000;

    /**
     * The total amount of award points available.
     */
    uint256 public constant TOTAL_POINTS_CAP = FIRST_MONTH_TOKEN_SUPPLY;

    /**
     * Number of seconds per day.
     */
    uint256 private constant SECONDS_PER_DAY = 60 * 60 * 24;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * Called after an upgrade. Typical initialize method is not called during upgrade.
     */
    function initializeAfterUpgrade(
        address newPresenter
    ) public reinitializer(2) {
        if (presenterContract != address(0)) {
            revert("presenterContract already set");
        }
        if (newPresenter == address(0)) {
            revert("newPresenterAddress has value of 0");
        }
        presenterContract = newPresenter;
        maximumUserTransactionsPerDay = 3;
    }

    /**
     * A modifier throwing when called by any account other than the selected
     * award presenter.
     */
    modifier onlyPresenter() {
        if (msg.sender != presenterContract) {
            revert("caller is not the award presenter");
        }
        _;
    }

    /**
     * Awards the default amount of points to the specified users. If one of
     * the users has reached daily limit, this function skips their account and
     * emits the token points limit reached event.
     */
    function awardDefaultAmountTo(
        address[2] memory users
    ) public onlyPresenter {
        awardTo(users[0], POINTS_PER_AWARD);
        awardTo(users[1], POINTS_PER_AWARD);
    }

    /**
     * Awards the given amount of points to the barq token to the specified
     * user. If one of the users has reached daily limit, this function skips
     * their account and emits the token claims limit reached event.
     */
    function awardTo(address user, uint256 amount) public onlyPresenter {
        if (_willExceedeDailyQuota(user, amount)) {
            emit DailyAwardPointsLimitReached(user);
            return;
        }

        if (_willExceedeTotalCap(amount)) {
            emit TotalAwardPointsLimitReached();
            return;
        }

        _updateDailyAmount(user, amount);
        _updateTotalAmount(user, amount);
    }

    /**
     * Returns current award points balance of the specified user.
     */
    function balanceOf(address user) public view returns (uint256) {
        return awardedPoints[user];
    }

    /**
     * Returns the number of maximum awarded user transactions per day.
     */
    function maximumAwardedUserTransactionsPerDay()
        public
        view
        returns (uint256)
    {
        return maximumUserTransactionsPerDay;
    }

    /**
     * Maximum number of points allowed to be awarded per user per day.
     */
    function maximumPointsPerDay() public view returns (uint256) {
        return maximumUserTransactionsPerDay * POINTS_PER_AWARD;
    }

    /**
     * Sets the number of maximum awarded user transactions per day.
     */
    function setMaximumAwardedUserTransactionsPerDay(
        uint256 value
    ) public onlyOwner {
        if (value <= 0) {
            revert(
                "Daily awarded transactions count maximum must be greater than 0"
            );
        }

        maximumUserTransactionsPerDay = value;
        emit MaximumAwardedUserTransactionsPerDayChanged(value);
    }

    /**
     * Returns address of the contract allowed to award the points.
     */
    function presenter() public view returns (address) {
        return presenterContract;
    }

    /**
     * Returns the amount of points for which the given user is still eligible
     * today.
     */
    function remainingUserSupply(address user) public view returns (uint256) {
        uint256 currentDay = _currentDay();

        return
            Math.min(
                maximumPointsPerDay() - dailyAwardedPoints[currentDay][user],
                remainingSupply()
            );
    }

    /**
     * Returns the amount of points still available for awards.
     */
    function remainingSupply() public view returns (uint256) {
        return TOTAL_POINTS_CAP - awardedPointsCount;
    }

    /**
     * Sets the address of the address allowed to award the points. By default
     * that's the contract's owner.
     */
    function setPresenter(address newPresenter) public onlyOwner {
        if (newPresenter == address(0)) {
            revert("Probably missing presenter parameter");
        }

        presenterContract = newPresenter;

        emit PresenterChanged(newPresenter);
    }

    /**
     * Returns the amount points in existence.
     */
    function totalSupply() public pure returns (uint256) {
        return TOTAL_POINTS_CAP;
    }

    function _currentDay() private view returns (uint256) {
        return block.timestamp / SECONDS_PER_DAY;
    }

    function _updateDailyAmount(
        address user,
        uint256 amount
    ) private onlyPresenter {
        uint256 currentDay = _currentDay();

        // We're comparing the timestamps here and those are under control of
        // miners, so by manipulating them someone could award themselves more
        // points than the limit. That's an acceptable risk IMO.
        //
        // slither-disable-next-line timestamp
        if (currentDay != lastAwardDay) {
            uint256 lastAwardedUsersListLength = lastAwardedUsersList.length;

            for (uint256 i = 0; i < lastAwardedUsersListLength; ++i) {
                delete dailyAwardedPoints[lastAwardDay][
                    lastAwardedUsersList[i]
                ];
            }
            delete lastAwardedUsersList;
            lastAwardDay = currentDay;
        }
        lastAwardedUsersList.push(user);
        dailyAwardedPoints[currentDay][user] += amount;
    }

    function _updateTotalAmount(
        address user,
        uint256 amount
    ) private onlyPresenter {
        awardedPointsCount += amount;
        awardedPoints[user] += amount;
    }

    function _willExceedeDailyQuota(
        address user,
        uint256 amount
    ) private view returns (bool) {
        uint256 currentDay = _currentDay();

        return
            dailyAwardedPoints[currentDay][user] + amount >
            maximumPointsPerDay();
    }

    function _willExceedeTotalCap(uint256 amount) private view returns (bool) {
        return awardedPointsCount + amount > TOTAL_POINTS_CAP;
    }
}

