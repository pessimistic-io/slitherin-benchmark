// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;
import "./Ownable.sol";

contract Feeable is Ownable {
    uint8 public feePercent;

    constructor() {
        feePercent = 80;
    }

    function setFeePercent(uint8 _feePercent) public onlyOwner {
        feePercent = _feePercent;
    }

    function minFee() public view returns (uint256) {
        return (tx.gasprice * gasleft() * feePercent) / 100;
    }
}

