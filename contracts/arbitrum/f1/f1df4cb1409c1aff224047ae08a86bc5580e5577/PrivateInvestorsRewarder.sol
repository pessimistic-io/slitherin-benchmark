// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IERC20} from "./IERC20.sol";
import {IVester} from "./IVester.sol";
import {IPrivateInvestors} from "./IPrivateInvestors.sol";

contract PrivateInvestorsRewarder is Util {
    mapping(address => uint256) public claimed;
    IPrivateInvestors public privateInvestors;
    IVester public vester;
    IERC20 public token;
    uint256 public totalRewards;
    uint256 public totalClaimed;
    uint256 public scheduleCliff = 0;
    uint256 public scheduleInitial = 0.05e18;
    uint256 public scheduleDuration = 365 days;

    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);
    event Donated(uint256 amount);
    event Claimed(address indexed target, uint256 amount);

    error DepositsTimeIsNotOver();

    constructor(address _privateInvestors, address _vester, address _token) {
        privateInvestors = IPrivateInvestors(_privateInvestors);
        vester = IVester(_vester);
        token = IERC20(_token);
        exec[msg.sender] = true;
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "scheduleCliff") scheduleCliff = data;
        if (what == "scheduleInitial") scheduleInitial = data;
        if (what == "scheduleDuration") scheduleDuration = data;
        emit File(what, data);
    }

    function file(bytes32 what, address data) public auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "privateInvestors") privateInvestors = IPrivateInvestors(data);
        if (what == "vester") vester = IVester(data);
        if (what == "token") token = IERC20(data);
        emit File(what, data);
    }

    function donate(uint256 amount) external auth {
        if (block.timestamp < privateInvestors.depositEnd()) revert DepositsTimeIsNotOver();
        pull(token, msg.sender, amount);
        totalRewards += amount;
        emit Donated(amount);
    }

    function claim() external {
        (uint256 totalDepositedAmount, uint256 depositedAmount) = getPrivateInvestorInfo(msg.sender);
        uint256 claimable = (totalRewards * depositedAmount / totalDepositedAmount) - claimed[msg.sender];

        if (claimable > 0) {
            claimed[msg.sender] += claimable;
            totalClaimed += claimable;

            token.approve(address(vester), claimable);
            vester.vest(4, msg.sender, address(token), claimable, scheduleInitial, scheduleCliff, scheduleDuration);

            emit Claimed(msg.sender, claimable);
        }
    }

    function getInfo(address investor) external view returns (uint256, uint256, uint256, uint256) {
        (uint256 totalDepositedAmount, uint256 depositedAmount) = getPrivateInvestorInfo(investor);
        uint256 investorRewards = totalRewards * depositedAmount / totalDepositedAmount;

        return (totalRewards, investorRewards, totalClaimed, claimed[investor]);
    }

    function getPrivateInvestorInfo(address investor)
        private
        view
        returns (uint256 totalDepositedAmount, uint256 depositedAmount)
    {
        totalDepositedAmount = privateInvestors.totalDeposits();
        (depositedAmount,) = privateInvestors.users(investor);
    }
}

