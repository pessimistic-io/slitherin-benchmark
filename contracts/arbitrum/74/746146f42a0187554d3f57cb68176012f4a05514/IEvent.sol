// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.4;

import "./EDataTypes.sol";
pragma experimental ABIEncoderV2;

interface IEvent {
    function info(uint256 _eventId) external view returns (EDataTypes.Event memory _event);

    function createSingleEvent(
        uint256[5] memory _numInfos,
        address[3] memory _addresses,
        uint256[] calldata _odds,
        string memory _datas,
        bool _affiliate
    ) external returns (uint256 _idx);
}

