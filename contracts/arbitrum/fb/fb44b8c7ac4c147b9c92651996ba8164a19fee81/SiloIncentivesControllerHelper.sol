// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "./SiloIncentivesController.sol";

contract SiloIncentivesControllerHelper {
    function getBalances(SiloIncentivesController _controller, address[] calldata _assets, address[] calldata _users)
        external
        view
        returns (uint256[] memory balances)
    {
        balances = new uint256[](_users.length);

        for (uint256 i; i < _users.length;) {
            balances[i] = _controller.getRewardsBalance(_assets, _users[i]);
            unchecked { i++; }
        }
    }
}

