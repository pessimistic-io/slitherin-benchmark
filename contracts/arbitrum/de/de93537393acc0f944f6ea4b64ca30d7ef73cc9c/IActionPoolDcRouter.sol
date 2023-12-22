// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IActionPoolDcRouter {
    function setRelayer(address _newRelayer) external;

    function performAction(
        uint256 _strategyId,
        bytes memory _funcSign,
        uint16 _receiverId,
        bytes memory _receiverAddress,
        uint256 _gasForDstLzReceive
    ) external payable;

    function bridge(
        address _receiverStableToken,
        uint256 _stableAmount,
        uint16 _finalRecipientId,
        address _finalRecipient,
        address _finalStableToken,
        uint16 _receiverId,
        bytes memory _receiverAddress,
        uint256 _gasAmount,
        uint256 _nativeForDst
    ) external payable;

    function bridgeToNative(
        address _nativeRecipient,
        address _nativeStableToken,
        uint256 _stableAmount,
        uint16 _receiverLZId,
        address _receiverAddress,
        address _destinationStableToken
    ) external payable;

    function initNewBB(
        uint256 _strategyId,
        address _implementation,
        bytes memory _constructorData,
        uint16 _fabricID,
        bytes memory _bbFabric,
        uint256 _gasForDstLzReceive
    ) external payable;

    function upgradeBB(
        uint256 _strategyId,
        address _proxy,
        address _newImplementation,
        uint16 _fabricID,
        bytes memory _bbFabric,
        uint256 _gasForDstLzReceive
    ) external payable;

    function approveWithdraw(
        uint256 _withdrawalId,
        uint256 _stableDeTokenPrice,
        uint256 _strategyId,
        uint16 _recipientId,
        bytes memory _recipient,
        uint256 _gasForDstLzReceive
    ) external payable;

    function cancelWithdraw(
        address _user,
        uint256 _strategyId,
        uint16 _recipientId,
        bytes memory _recipient,
        uint256 _gasForDstLzReceive
    ) external payable;

    function setBridge(
        address _newSgBridge,
        uint256 _strategyId,
        uint16 _recipientId,
        bytes memory _recipient,
        uint256 _gasForDstLzReceive
    ) external payable;

    function setStable(
        address _newStableToken,
        uint256 _strategyId,
        uint16 _recipientId,
        bytes memory _recipient,
        uint256 _gasForDstLzReceive
    ) external payable;

    function getNativeChainId() external view returns (uint16);

    function getDeCommasTreasurer() external view returns (address);
}

