// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;
pragma abicoder v2;

interface IDelegateApproval {
    /// @param trader The address of trader
    /// @param delegate The address of delegate
    /// @param actions The actions to be approved
    event DelegationApproved(address indexed trader, address delegate, uint8 actions);

    /// @param trader The address of trader
    /// @param delegate The address of delegate
    /// @param actions The actions to be revoked
    event DelegationRevoked(address indexed trader, address delegate, uint8 actions);

    /// @param delegate The address of delegate
    /// @param actions The actions to be approved
    function approve(address delegate, uint8 actions) external;

    /// @param delegate The address of delegate
    /// @param actions The actions to be revoked
    function revoke(address delegate, uint8 actions) external;

    /// @return action The value of action `_CLEARINGHOUSE_OPENPOSITION`
    function getClearingHouseOpenPositionAction() external pure returns (uint8);

    /// @return action The value of action `_CLEARINGHOUSE_CLOSEPOSITION`
    function getClearingHouseClosePositionAction() external pure returns (uint8);

    /// @return action The value of action `_CLEARINGHOUSE_ADDMARGIN`
    function getClearingHouseAddMarginAction() external pure returns (uint8);

    /// @return action The value of action `_CLEARINGHOUSE_REMOVEMARGIN`
    function getClearingHouseRemoveMarginAction() external pure returns (uint8);

    /// @param trader The address of trader
    /// @param delegate The address of delegate
    /// @return actions The approved actions
    function getApprovedActions(address trader, address delegate) external view returns (uint8);

    /// @param trader The address of trader
    /// @param delegate The address of delegate
    /// @param actions The actions to be checked
    /// @return true if delegate is allowed to perform **each** actions for trader, otherwise false
    function hasApprovalFor(
        address trader,
        address delegate,
        uint8 actions
    ) external view returns (bool);

    /// @param trader The address of trader
    /// @param delegate The address of delegate
    /// @return true if delegate can open position for trader, otherwise false
    function canOpenPositionFor(address trader, address delegate) external view returns (bool);

    /// @param trader The address of trader
    /// @param delegate The address of delegate
    /// @return true if delegate can close position for trader, otherwise false
    function canClosePositionFor(address trader, address delegate) external view returns (bool);

    /// @param trader The address of trader
    /// @param delegate The address of delegate
    /// @return true if delegate can add margin for trader, otherwise false
    function canAddMarginFor(address trader, address delegate) external view returns (bool);

    /// @param trader The address of trader
    /// @param delegate The address of delegate
    /// @return true if delegate can remove margin for trader, otherwise false
    function canRemoveMarginFor(address trader, address delegate) external view returns (bool);
}
