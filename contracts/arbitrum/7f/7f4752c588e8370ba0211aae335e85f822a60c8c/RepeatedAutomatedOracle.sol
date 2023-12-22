// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Ownable.sol";

import "./IOracleId.sol";

contract RepeatedAutomatedOracle is Ownable {
    bytes4 private constant _SELECTOR = bytes4(keccak256("triggerOracle()"));
    
    IOracleId private _oracleId;
    uint256 private _nextTimestamp;
    uint256 private _period;

    constructor(
        IOracleId oracleId_,
        uint256 nextTimestamp_,
        uint256 period_
    ) {
        _oracleId = oracleId_;
        _nextTimestamp = nextTimestamp_;
        _period = period_;
    }

    // Trigger
    function triggerOracle() public {
        _oracleId._callback(_nextTimestamp);
        _nextTimestamp += _period;
    }

    // Getters
    function getOracleId() external view returns (address) {
        return address(_oracleId);
    }

    function getNextTimestamp() external view returns (uint256) {
        return _nextTimestamp;
    }

    function getPeriod() external view returns (uint256) {
        return _period;
    }

    function checker() external view returns (bool canExec, bytes memory execPayload) {
        canExec = _nextTimestamp < block.timestamp;
        execPayload = abi.encodeWithSelector(_SELECTOR);
    }

    // Governance
    function setOracleId(IOracleId oracleId_) external onlyOwner {
        _oracleId = oracleId_;
    }

    function setNextTimestamp(uint256 nextTimestamp_) external onlyOwner{
        _nextTimestamp = nextTimestamp_;
    }

    function setPeriod(uint256 period_) external onlyOwner {
        _period = period_;
    }
}

