// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./ERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";


contract muchoBadgeManagerMock is Ownable {
    using SafeMath for uint256;

    struct Plan {
        uint256 id;
        string name;
        string uri;
        uint256 subscribers;
        Price subscriptionPrice;
        Price renewalPrice;
        uint256 time;
        bool exists;
        bool enabled;
    }

    struct Price {
        address token;
        uint256 amount;
    }

    mapping(address => uint256[]) userToPlan;

    function addPlan(address _user, uint256 _planId) external onlyOwner{
        userToPlan[_user].push(_planId);
    }

    function activePlansForUser(address _user) external view returns (Plan[] memory){
        uint256[] memory pids = userToPlan[_user];
        Plan[] memory plans = new Plan[](pids.length);
        for(uint256 i = 0; i < plans.length; i++){
            plans[i] = Plan(pids[i], '', '', 0, Price(address(0), 0), Price(address(0), 0), 0, true, true);
        }

        return plans;
    }

}
