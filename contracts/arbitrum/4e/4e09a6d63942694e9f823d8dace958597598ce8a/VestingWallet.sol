pragma solidity ^0.8.18;

import "./IERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

contract VestingWallet is OwnableUpgradeable {
    IERC20Upgradeable public token;
    mapping(address => uint256) public balances;
    mapping(address => VestingSchedule[]) public vestingSchedules;
    mapping(address => uint256) public vestingScheduleCounter;

    uint256 private _duration;
    uint256 private _interval;

    struct VestingSchedule {
        uint256 amount;
        uint256 start;
        uint256 released;
    }

    event VestingAdded(address investor, uint256 amount, uint256 created);
    event VestingReleased(address withdrawer, uint256 amount, uint256 released);

    function initialize(address _token) public initializer {
        __Ownable_init();
        _duration = 180 * 86400; // 180 days
        _interval = 45 * 86400; // 45 days

        token = IERC20Upgradeable(_token);
    }

    function addVestingSchedule(
        address _investor,
        uint256 _amount
    ) public onlyOwner {
        require(_investor != address(0), "Invalid investor address");
        require(_amount > 0, "Amount must be greater than 0");

        VestingSchedule memory schedule = VestingSchedule({
            amount: _amount,
            start: block.timestamp,
            released: 0
        });

        vestingSchedules[_investor].push(schedule);
        vestingScheduleCounter[_investor]++;

        require(
            token.transferFrom(_msgSender(), address(this), _amount),
            "Transfer failed"
        );

        balances[address(this)] += _amount;

        emit VestingAdded(_investor, _amount, block.timestamp);
    }

    function release() public {
        VestingSchedule[] storage schedules = vestingSchedules[_msgSender()];
        uint256 totalVested = 0;

        for (uint256 i = 0; i < schedules.length; i++) {
            VestingSchedule storage schedule = schedules[i];
            uint256 vested = calculateVested(schedule);

            if (vested > schedule.released) {
                uint256 amount = vested - schedule.released;
                schedule.released = vested;
                totalVested += amount;
            }
        }

        require(totalVested > 0, "No tokens vested");

        require(token.transfer(_msgSender(), totalVested), "Transfer failed");
        balances[address(this)] -= totalVested;
        balances[_msgSender()] += totalVested;

        emit VestingReleased(_msgSender(), totalVested, block.timestamp);
    }

    function calculateVested(
        VestingSchedule storage schedule
    ) internal view returns (uint256) {
        uint256 currentTime = block.timestamp;

        uint256 elapsed = currentTime - schedule.start;

        if (elapsed < 0) {
            return 0;
        }

        if (elapsed >= _duration) {
            return schedule.amount;
        }

        uint256 numIntervals = elapsed / _interval;
        uint256 vestedPerInterval = schedule.amount / (_duration / _interval);
        uint256 vested = numIntervals * vestedPerInterval;

        if (vested > schedule.amount) {
            vested = schedule.amount;
        }

        return vested;
    }

    function getAllVestingSchedules(
        address _account
    ) external view returns (VestingSchedule[] memory) {
        VestingSchedule[] memory tVestingSchedules = new VestingSchedule[](
            vestingScheduleCounter[_account]
        );
        for (uint256 i = 0; i < vestingScheduleCounter[_account]; i++) {
            tVestingSchedules[i] = vestingSchedules[_account][i];
        }
        return tVestingSchedules;
    }
}

