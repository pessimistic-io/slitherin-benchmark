// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

/**
 * @title Vesting
 * @author gotbit
 */

import "./IVesting.sol";
import "./ILaunchpad.sol";
import "./Initializable.sol";

contract VestingProxy is IVesting2, Initializable {
    uint8 public round;
    ILaunchpad public launchpad;
    address public manager;
    Unlock[] public schedule; // MUST BE SORTED!!!

    mapping(address => uint256) public claimed;

    constructor() {
        _disableInitializers();
    }

    modifier afterInit() {
        require(address(launchpad) != address(0), 'not initialized yet');
        _;
    }

    function initialize(
        uint8 round_,
        address launchpad_, // TODO: add decimals
        Unlock[] calldata schedule_,
        address manager_
    ) external initializer {
        uint256 percentageSum = 0;
        uint256 latestTimestamp = 0;

        for (uint256 i; i < schedule_.length; ) {
            uint256 timestamp = schedule_[i].datetime;
            require(timestamp > latestTimestamp, 'vesting dates are not sorted');
            latestTimestamp = timestamp;

            percentageSum += schedule_[i].percentage;
            schedule.push(schedule_[i]);
            unchecked {
                ++i;
            }
        }

        require(percentageSum == 1 ether, 'schedule doesnt unlock 100%');

        round = round_;
        launchpad = ILaunchpad(launchpad_);
        manager = manager_;
    }

    function changeSchedule(Unlock[] calldata schedule_) external afterInit {
        require(msg.sender == manager, 'not manager');
        require(launchpad.startTime() + launchpad.duration() > block.timestamp, 'launchpad in progress');

        uint256 percentageSum = 0;
        uint256 latestTimestamp = 0;

        delete schedule;

        for (uint256 i; i < schedule_.length; ) {
            uint256 timestamp = schedule_[i].datetime;
            require(timestamp > latestTimestamp, 'vesting dates are not sorted');
            latestTimestamp = timestamp;

            percentageSum += schedule_[i].percentage;
            schedule.push(schedule_[i]);
            unchecked {
                ++i;
            }
        }

        require(percentageSum == 1 ether, 'schedule doesnt unlock 100%');
    }

    function unlocked(address user) public view returns (uint256) {
        uint256 userTotal = launchpad.userTotal(user);
        uint256 percentage = 0;

        uint256 scheduleLength_ = schedule.length;
        for (uint256 i; i < scheduleLength_; ) {
            Unlock memory unlock = schedule[i];
            if (unlock.datetime > block.timestamp) break;
            percentage += unlock.percentage;

            unchecked {
                ++i;
            }
        }

        return (userTotal * percentage) / 1 ether;
    }

    function claim(address investor) external afterInit {
        require(!launchpad.launchFailed(), 'launch has failed, refunding investors mode');
        require(msg.sender == manager, 'not manager');
        require(!launchpad.paidBack(investor), 'paid back');

        // this will be 0 before the launch ends so we don't need a separate check for that
        uint256 projectAmountClaimed = unlocked(investor);
        unchecked {
            projectAmountClaimed -= claimed[investor];
        }
        require(projectAmountClaimed > 0, 'nothing to claim');
        claimed[investor] += projectAmountClaimed;
        emit Claim(investor, projectAmountClaimed);

        launchpad.transferProjectToken(projectAmountClaimed, investor);

        uint256 stableAmount = (projectAmountClaimed * launchpad.price()) /
            launchpad.oneProjectToken();
        uint256 comission = (stableAmount * launchpad.launchpadKickback()) / 1 ether;

        launchpad.transferStableToken(
            stableAmount - comission,
            launchpad.projectWallet()
        );
        launchpad.transferStableToken(comission, launchpad.kickbackWallet());
    }

    function getSchedule() external view returns (Unlock[] memory) {
        return schedule;
    }

    function scheduleLength() external view returns (uint256) {
        return schedule.length;
    }

    function vestingEndTime() external view returns (uint256) {
        return schedule[schedule.length - 1].datetime;
    }
}

