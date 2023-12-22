// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// =========================== FraxGovernor ===========================
// ====================================================================
// # FraxGovernor

// # Overview

// # Requirements

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jon Walch: https://github.com/jonwalch

import { FraxGovernorBase, ConstructorParams as FraxGovernorBaseParams } from "./FraxGovernorBase.sol";
import { FraxGovernorOmega } from "./FraxGovernorOmega.sol";
import { FraxVotingDelegation } from "./FraxVotingDelegation.sol";
import { IFraxGovernorAlpha } from "./IFraxGovernorAlpha.sol";

struct ConstructorParams {
    address veFxs;
    address[] safeAllowlist;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
    uint256 initialProposalThreshold;
    uint256 initialQuorum;
    uint256 initialShortCircuitThreshold;
}

/**
 * @notice Voting contract for veFXS holders
 */
contract FraxGovernorAlpha is FraxVotingDelegation, FraxGovernorBase {
    //mapping(address safe => uint256 status) public gnosisSafeAllowlist;
    mapping(address => uint256) public gnosisSafeAllowlist;

    event SafeRegistered(address safe);
    event SafeUnregistered(address safe);

    constructor(
        ConstructorParams memory params
    )
        FraxVotingDelegation(params.veFxs)
        FraxGovernorBase(
            FraxGovernorBaseParams({
                veFxs: params.veFxs,
                _name: "FraxGovernorAlpha",
                initialVotingDelay: params.initialVotingDelay,
                initialVotingPeriod: params.initialVotingPeriod,
                initialProposalThreshold: params.initialProposalThreshold,
                initialQuorum: params.initialQuorum,
                initialShortCircuitThreshold: params.initialShortCircuitThreshold
            })
        )
    {
        for (uint256 i = 0; i < params.safeAllowlist.length; ++i) {
            gnosisSafeAllowlist[params.safeAllowlist[i]] = 1;
            emit SafeRegistered(params.safeAllowlist[i]);
        }
    }

    function _getVotes(
        address account,
        uint256 timepoint,
        bytes memory /* params */
    ) internal view override returns (uint256) {
        return _getVoteWeight(account, timepoint);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        _requireVeFxsProposalThreshold();
        return _propose(targets, values, calldatas, description);
    }

    function setVotingQuorum(uint256 _votingQuorum) external onlyGovernance {
        _setVotingQuorum(_votingQuorum);
    }

    function setShortCircuitThreshold(uint256 _shortCircuitThreshold) external onlyGovernance {
        _setShortCircuitThreshold(_shortCircuitThreshold);
    }

    // safes are expected to be properly configured before calling this function. At time of writing,
    // they should have the FraxGuard set, have FraxGovernorOmega set as a signer and set FraxGovernor Alpha as Module
    function addSafesToAllowlist(address[] calldata safes) external onlyGovernance {
        for (uint256 i = 0; i < safes.length; ++i) {
            gnosisSafeAllowlist[safes[i]] = 1;
            emit SafeRegistered(safes[i]);
        }
    }

    // safes are expected to have configuration removed before calling this function. At time of writing,
    // they should have the FraxGuard removed, have FraxGovernorOmega removed as a signer, and should have
    // removed FraxGovernorAlpha as a module. This can all be done in one proposal, since FraxGovernorAlpha
    // can do it all itself.
    function removeSafesFromAllowlist(address[] calldata safes) external onlyGovernance {
        for (uint256 i = 0; i < safes.length; ++i) {
            delete gnosisSafeAllowlist[safes[i]];
            emit SafeUnregistered(safes[i]);
        }
    }
}

