// SPDX-License-Identifier: UNLICENSED
// © Copyright AutoDCA. All Rights Reserved
pragma solidity 0.8.9;

import "./Ownable2Step.sol";

import "./IFeeOracle.sol";
import "./IFeeCollector.sol";

abstract contract CollectFees is Ownable2Step {
    address public feeCollectorAddress;
    address public feeOracleAddress;

    event SetFeeCollectorAddress(address newFeeCollectorAddress);
    event SetFeeOracleAddress(address newFeeOracleAddress);

    constructor(address feeCollectorAddress_, address feeOracleAddress_) {
        feeCollectorAddress = feeCollectorAddress_;
        feeOracleAddress = feeOracleAddress_;
    }

    function setFeeCollectorAddress(
        address feeCollectorAddress_
    ) public onlyOwner {
        feeCollectorAddress = feeCollectorAddress_;
        emit SetFeeCollectorAddress(feeCollectorAddress_);
    }

    function setFeeOracleAddress(address feeOracleAddress_) public onlyOwner {
        feeOracleAddress = feeOracleAddress_;
        emit SetFeeOracleAddress(feeOracleAddress_);
    }

    modifier collectFee() {
        uint256 fee = IFeeOracle(feeOracleAddress).getFee();
        require(msg.value >= fee, "Not enough funds");
        IFeeCollector(feeCollectorAddress).receiveNative{value: fee}();
        _;
    }

    function getFeeFromOracle() public view returns (uint256) {
        uint256 fee = IFeeOracle(feeOracleAddress).getFee();
        return fee;
    }
}

