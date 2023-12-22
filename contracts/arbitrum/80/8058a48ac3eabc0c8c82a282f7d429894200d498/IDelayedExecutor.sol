// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDelayedExecutor {
    event TxRequested(address indexed _sender, uint256 indexed _id, uint256 date, address indexed _destination, bytes _message);
    event TxExecuted(address indexed _sender, uint256 indexed _id);
    event TxCancelled(address indexed _sender, uint256 indexed _id);

    struct Transaction {
        uint256 date;
        bytes message;
        address destination;
        address sender;
    }

    function transactions(uint256 id) external view returns (uint256 _date, bytes memory _message, address _destination, address _sender);
    function delay() external view returns (uint256);
    function minDelay() external view returns (uint256);
    function setDelay(uint256 _delay) external;
    function requestTx(address _destination, bytes calldata _message) external returns (uint256 _id);
    function executeTx(uint256 _id) external;
    function cancelTx(uint256 _id) external;
}
