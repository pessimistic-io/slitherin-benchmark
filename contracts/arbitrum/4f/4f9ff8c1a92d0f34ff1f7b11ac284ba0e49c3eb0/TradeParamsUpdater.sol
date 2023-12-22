// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DelayedExecutor.sol";
import "./ITrade.sol";
import "./ITradeParamsUpdater.sol";

contract TradeParamsUpdater is ITradeParamsUpdater, DelayedExecutor {
    mapping(address => uint256) public lastTxs;

    constructor(uint256 _updatePeriod, uint256 _minDelay) DelayedExecutor(_updatePeriod, _minDelay) {}

    function requestTx(address _destination, bytes calldata _message) public override returns (uint256 _id) {
        if (lastTxs[_destination] != 0) {
            _cancelTx(lastTxs[_destination]);
        }
        uint256 _id = super.requestTx(_destination, _message);
        lastTxs[_destination] = _id;
    }

    function cancelTx(uint256 _id) public override {
        _cancelTx(_id);
    }

    function executeTx(uint256 _id) public override {
        address destination = transactions[_id].destination;
        super.executeTx(_id);
        delete lastTxs[destination];
    }

    function nearestUpdate(address _destination) external view returns (uint256) {
        return transactions[lastTxs[_destination]].date;
    }

    function _cancelTx(uint256 _id) private {
        address destination = transactions[_id].destination;
        super.cancelTx(_id);
        delete lastTxs[destination];
    }

    function _authorizeTx(address _destination, bytes memory message) internal override {
        require(ITrade(_destination).isManager(msg.sender), "TPU/AD"); // access denied
    }
}
