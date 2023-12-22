// SPDX-License-Identifier: UNLINCESED
pragma solidity 0.8.20;

import { LibFeeCollector } from "./LibFeeCollector.sol";
import { LibAccessControl } from "./LibAccessControl.sol";
import { LibDiamond } from "./LibDiamond.sol";
import { LibAsset } from "./LibAsset.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

error CannotAuthoriseSelf();
error IncorrectFeePercent();
error InvalidFeeAmount();

contract FeeManagerFacet is ReentrancyGuard{

    event MainPartnerChanged(address newMainPartner);

    function updateMainPartner(address _mainPartner) external {
        if (LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();

        if (_mainPartner == address(this)) revert CannotAuthoriseSelf();

        LibFeeCollector.updateMainPartner(_mainPartner);

        emit MainPartnerChanged(_mainPartner);
    }

    function updateMainFee(uint256 _mainFee) external {
        if (LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();

        if (_mainFee > 10000) revert IncorrectFeePercent();

        LibFeeCollector.updateMainFee(_mainFee);
    }

    function addPartnerInfo(address _partner, uint256 _partnerFeeShare) external {
        if (LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();

        if (_partnerFeeShare > 10000) revert IncorrectFeePercent();
        if (_partner == address(this)) revert CannotAuthoriseSelf();

        LibFeeCollector.addPartner(_partner, _partnerFeeShare);
    }

    function removePartnerInfo(address _partner) external {
        if (LibDiamond.contractOwner() != msg.sender) LibAccessControl.isAllowedTo();

        (bool isPartner,) = LibFeeCollector.getPartnerInfo(_partner);
        if (!isPartner) return;

        LibFeeCollector.removePartner(_partner);
    }

    function getPartnerInfo(address _partner) external view returns (bool, uint256) {
        return LibFeeCollector.getPartnerInfo(_partner);
    }

    function getFeeBalance(address _token) external view returns (uint256) {
        return LibFeeCollector.getFeeAmount(_token, msg.sender);
    }

    function batchGetFeeBalance(address[] calldata _tokens) external view returns (uint256[] memory) {
        uint256 length = _tokens.length;
        uint256[] memory balances = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            balances[i] = LibFeeCollector.getFeeAmount(_tokens[i], msg.sender);
        }

        return balances;
    }

    function getMainInfo() external view returns (address, uint256) {
        address mainPartner = LibFeeCollector.getMainPartner();
        uint256 mainFee = LibFeeCollector.getMainFee();
        return (mainPartner, mainFee);
    }

    function withdrawFee(address _token, uint256 _amount) external nonReentrant {
        uint256 totalFee = LibFeeCollector.getFeeAmount(_token, msg.sender);
        if (totalFee < _amount) revert InvalidFeeAmount();

        LibFeeCollector.decreaseFeeAmount(_amount, msg.sender, _token);
        LibAsset.transferAsset(_token, payable(msg.sender), _amount);
    }
}
