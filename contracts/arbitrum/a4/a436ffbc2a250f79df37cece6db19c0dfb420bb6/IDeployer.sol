// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IEnums.sol";

interface IDeployer {
    function addToUserLaunchpad(
        address _user,
        address _token,
        IEnums.LAUNCHPAD_TYPE _launchpadType
    ) external;

    function changeLaunchpadState(address _token, uint256 _newState) external;

    function changeActionChanged(
        address _launchpad,
        bool _usingWhitelist,
        uint256 _endOfWhitelistTime
    ) external;

    function changeWhitelistUsers(
        address _launchpad,
        address[] memory _users,
        uint256 _action
    ) external;

    function launchpadRaisedAmountChangedReport(
        address _token,
        uint256 _currentRaisedAmount,
        uint256 _currentNeedToRaised
    ) external;
}

