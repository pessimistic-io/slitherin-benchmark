// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Gov} from "./Gov.sol";
import {GovToken} from "./GovToken.sol";
import {TimelockController} from "./TimelockController.sol";


contract GovDeployer  {
    function deploy(
        GovToken _token,
        TimelockController _timelock,
        string memory _name,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumNumerator,
        uint256 _proposalThreshold
    ) external returns (Gov) {
        return
            new Gov(
                _token,
                _timelock,
                _name,
                _votingDelay,
                _votingPeriod,
                _quorumNumerator,
                _proposalThreshold
            );
    }
}

