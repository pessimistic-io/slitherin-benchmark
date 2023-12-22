// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./IHotpotToken.sol";
import "./Governor.sol";
import "./IGovernor.sol";

library GovernorLib {
    event LogGovernorCreated(address proxyAddr, address govAddr);

    function createGovernorForToken(
        address proxyAddr,
        IGovernor.GovInfo calldata govInfo
    ) public {
        bytes32 projectAdminRole = IHotpotToken(proxyAddr)
            .getProjectAdminRole();
        require(
            IHotpotToken(proxyAddr).hasRole(projectAdminRole, msg.sender),
            "not project admin"
        );
        Governor gov = new Governor(
            govInfo.strategyReference,
            govInfo.strategy,
            govInfo.votingPeriod,
            govInfo.votingDelay,
            govInfo.proposalThreshold,
            govInfo.quorumVotes,
            govInfo.timelockDelay
        );
        IHotpotToken(proxyAddr).setGov(address(gov.timelock()));
        emit LogGovernorCreated(address(proxyAddr), address(gov));
    }
}

