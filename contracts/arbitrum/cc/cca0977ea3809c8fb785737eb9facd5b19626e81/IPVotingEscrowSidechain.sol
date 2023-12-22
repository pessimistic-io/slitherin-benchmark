// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.17;

import "./IPVeToken.sol";
import "./VeBalanceLib.sol";
import "./VeHistoryLib.sol";

interface IPVotingEscrowSidechain is IPVeToken {
    event SetNewDelegator(address delegator, address receiver);

    event SetNewTotalSupply(VeBalance totalSupply);

    event SetNewUserPosition(LockedPosition position);

    /// @notice Get the last time the vePENDLE total supply was broadcasted to this chain.
    function lastTotalSupplyReceivedAt() external view returns (uint256);

    /// @notice Returns the delegator of the user. If set, querying the vePENDLE balance of the user will return
    /// the balance of the delegator.
    /// @notice Due to some issues, this mapping can only be read off-chain.
    // function delegatorOf(address user) external view returns (address)
}

