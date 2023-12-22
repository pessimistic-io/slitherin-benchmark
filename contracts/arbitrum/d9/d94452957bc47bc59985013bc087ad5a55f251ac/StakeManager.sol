// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IRewardTracker.sol";
import "./Governable.sol";

contract StakeManager is Governable {
    function stakeForAccount(
        address _rewardTracker,
        address _account,
        address _token,
        uint256 _amount
    ) external onlyGov {
        IRewardTracker(_rewardTracker).stakeForAccount(_account, _account, _token, _amount);
    }
}

