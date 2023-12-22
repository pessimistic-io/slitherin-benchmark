// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

import "./TryCall.sol";
import "./IDelayedExecutor.sol";

abstract contract DelayedExecutor is IDelayedExecutor, Ownable {
    mapping(uint256 => Transaction) public transactions;
    uint256 public delay;
    uint256 public minDelay;

    constructor(uint256 _delay, uint256 _minDelay) {
        delay = _delay;
        minDelay = _minDelay;
        require(_delay >= minDelay, "DE/DS"); // delay too small
    }

    function setDelay(uint256 _delay) external onlyOwner {
        require(_delay >= minDelay, "DE/DS"); // delay too small
        delay = _delay;
    }
    
    function requestTx(address _destination, bytes calldata _message) public virtual returns (uint256 _id) {
        _authorizeTx(_destination, _message);
        uint256 executionDate = block.timestamp + delay;
        _id = uint256(keccak256(abi.encode(msg.sender, _destination, _message, executionDate)));
        transactions[_id] = Transaction(executionDate, _message, _destination, msg.sender);
        emit TxRequested(msg.sender, _id, executionDate, _destination, _message);
    }

    function executeTx(uint256 _id) public virtual {
        Transaction memory transaction = transactions[_id];
        require(transaction.date > 0, "DE/TXNF"); // transaction not found
        _authorizeTx(transaction.destination, transaction.message);
        require(transaction.date <= block.timestamp, "DE/DNP"); // delay not passed
        emit TxExecuted(msg.sender, _id);
        delete transactions[_id];
        TryCall.call(transaction.destination, transaction.message);
    }

    function cancelTx(uint256 _id) public virtual {
        _authorizeTx(transactions[_id].destination, transactions[_id].message);
        emit TxCancelled(transactions[_id].sender, _id);
        delete transactions[_id];
    }

    function _authorizeTx(address _destination, bytes memory message) internal virtual;
}

contract DummyDelayedExecutor is DelayedExecutor {
    constructor(uint256 _delay, uint256 _minDelay) DelayedExecutor(_delay, _minDelay) {}

    function _authorizeTx(address _destination, bytes memory message) internal override {}
}
