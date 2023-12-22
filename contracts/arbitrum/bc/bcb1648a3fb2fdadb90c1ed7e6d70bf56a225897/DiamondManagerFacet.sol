// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";
import "./LibPlexusUtil.sol";
import "./SafeERC20.sol";

contract DiamondManagerFacet {
    using SafeERC20 for IERC20;

    function feeAndReceiverUpdate(uint256 _newFee, address _newFeeReceiver) external {
        require(msg.sender == LibDiamond.contractOwner(), "no entry");
        LibDiamond.setFeePercent(_newFee);
        LibDiamond.setFeeReceiver(_newFeeReceiver);
    }

    function getReceiver() external view returns (address) {
        return LibPlexusUtil.getFeeReceiver();
    }

    function getFee() external view returns (uint256) {
        return LibPlexusUtil.getBridgeFee();
    }

    function setFee(uint256 _fee) external {
        require(msg.sender == LibDiamond.contractOwner() || msg.sender == LibDiamond.feeReceiver());
        LibDiamond.setFeePercent(_fee);
    }

    function setFeeReceiver(address _newReceiver) external {
        require(msg.sender == LibDiamond.contractOwner() || msg.sender == LibDiamond.feeReceiver());
        LibDiamond.setFeeReceiver(_newReceiver);
    }

    function EmergencyWithdraw(address _tokenAddress, uint256 amount) public {
        require(msg.sender == LibDiamond.contractOwner());
        bool isNotNative = !LibPlexusUtil._isNative(_tokenAddress);
        if (isNotNative) {
            IERC20(_tokenAddress).safeTransfer(LibDiamond.contractOwner(), amount);
        } else {
            LibPlexusUtil._safeNativeTransfer(LibDiamond.contractOwner(), amount);
        }
    }
}

