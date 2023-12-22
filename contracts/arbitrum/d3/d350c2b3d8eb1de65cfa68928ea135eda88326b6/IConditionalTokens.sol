//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IConditionalTokens {
    function splitPosition(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external;
    function mergePositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external;
    function reportPayouts(bytes32 questionId, uint[] calldata payouts) external;
    function prepareCondition(address oracle, bytes32 questionId, uint outcomeSlotCount) external;
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;
    function balanceOf(address owner, uint256 id) external view returns (uint256);
}
