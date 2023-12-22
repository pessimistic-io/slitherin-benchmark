// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IMuchoBadgeManager {
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

    function activePlansForUser(address _user) external view returns (Plan[] memory);

}

