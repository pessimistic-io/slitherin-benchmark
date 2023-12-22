// SPDX-License-Identifier: UNLINCESED
pragma solidity 0.8.20;

import { LibDiamond } from "./LibDiamond.sol";
import { LibAccessControl } from "./LibAccessControl.sol";
import { LibBridge } from "./LibBridge.sol";
import { NullAddrIsNotAnERC20Token } from "./GenericErrors.sol";
import { LibUtil } from "./LibUtil.sol";

error IncorrectFeePercent();
error LengthMismatch();

contract BridgeFacet  {
    function updateCrosschainFee(uint256 _crosschainFee) external {
        if(LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();

        if(_crosschainFee > 10000) revert IncorrectFeePercent();

        LibBridge.updateCrosschainFee(_crosschainFee);
    }

    function updateMinFee(uint256 _chainId, uint256 _minFee) external {
        if(LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();

        LibBridge.updateMinFee(_chainId, _minFee);
    }

    function batchUpdateMinFee(uint256[] calldata _chainId, uint256[] calldata _minFee) external {
        if(LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();

        uint256 length = _chainId.length;

        if (length != _minFee.length) revert LengthMismatch();

        for (uint256 i; i < length;) {

            LibBridge.updateMinFee(_chainId[i], _minFee[i]);

            unchecked {
                ++i;
            }
        }
    }

    function addApprovedToken(address _token) external {
        if(LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();

        if(LibUtil.isZeroAddress(_token)) revert NullAddrIsNotAnERC20Token();

        LibBridge.addApprovedToken(_token);
    }

    function removeApprovedToken(address _token) external {
        if(LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();
        LibBridge.removeApprovedToken(_token);
    }

    function addContractTo(uint256 _chainId, address _contractTo) external {
        if(LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();
        LibBridge.addContractTo(_chainId, _contractTo);
    }

    function removeContractTo(uint256 _chainId) external {
        if(LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();
        LibBridge.removeContractTo(_chainId);
    }

    function getContractTo(uint256 _chainId) external view returns (address) {
        if(LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();
        return LibBridge.getContractTo(_chainId);
    }

    function getCrosschainFee() external view returns (uint256) {
        return LibBridge.getCrosschainFee();
    }

    function getMinFee(uint256 _chainId) external view returns (uint256) {
        return LibBridge.getMinFee(_chainId);
    }

    function isTokenApproved(address _token) external view returns (bool) {
        return LibBridge.getApprovedToken(_token);
    }
}
