// This file is part of Darwinia.
// Copyright (C) 2018-2023 Darwinia Network
// SPDX-License-Identifier: GPL-3.0
//
// Darwinia is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Darwinia is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Darwinia. If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.17;

import "./BaseMessageLine.sol";
import "./LineLookup.sol";
import "./IORMP.sol";
import "./Application.sol";
import "./Ownable2Step.sol";

interface IChannel {
    function dones(bytes32 messageId) external view returns (bool);
}

contract ORMPLineExt is Ownable2Step, Application, BaseMessageLine, LineLookup {
    // Latest sent meesage id
    bytes32 public sentMessageId;

    // Latest recv meesage id
    bytes32 public recvMessageId;

    constructor(address dao, address ormp, string memory name) Application(ormp) BaseMessageLine(name) {
        _transferOwnership(dao);
    }

    function setURI(string calldata uri) external onlyOwner {
        _setURI(uri);
    }

    function setAppConfig(address oracle, address relayer) external onlyOwner {
        _setAppConfig(oracle, relayer);
    }

    function setToLine(uint256 _toChainId, address _toLineAddress) external onlyOwner {
        _setToLine(_toChainId, _toLineAddress);
    }

    function setFromLine(uint256 _fromChainId, address _fromLineAddress) external onlyOwner {
        _setFromLine(_fromChainId, _fromLineAddress);
    }

    function _toLine(uint256 toChainId) internal view returns (address) {
        return toLineLookup[toChainId];
    }

    function _fromLine(uint256 fromChainId) internal view returns (address) {
        return fromLineLookup[fromChainId];
    }

    function _send(address fromDapp, uint256 toChainId, address toDapp, bytes calldata message, bytes calldata params)
        internal
        override
    {
        (uint256 gasLimit, address refund, bytes memory ormpParams) = abi.decode(params, (uint256, address, bytes));
        bytes memory encoded = abi.encodeWithSelector(ORMPLineExt.recv.selector, fromDapp, toDapp, message);
        sentMessageId = IORMP(TRUSTED_ORMP).send{value: msg.value}(
            toChainId, _toLine(toChainId), gasLimit, encoded, refund, ormpParams
        );
    }

    function recv(address fromDapp, address toDapp, bytes calldata message) external payable onlyORMP {
        uint256 fromChainId = _fromChainId();
        require(_xmsgSender() == _fromLine(fromChainId), "!auth");
        recvMessageId = _messageId();
        _recv(fromChainId, fromDapp, toDapp, message);
    }

    function fee(uint256 toChainId, address toDapp, bytes calldata message, bytes calldata params)
        external
        view
        override
        returns (uint256)
    {
        (uint256 gasLimit,, bytes memory ormpParams) = abi.decode(params, (uint256, address, bytes));
        bytes memory encoded = abi.encodeWithSelector(ORMPLineExt.recv.selector, msg.sender, toDapp, message);
        return IORMP(TRUSTED_ORMP).fee(toChainId, address(this), gasLimit, encoded, ormpParams);
    }

    function dones(bytes32 _messageId) external view returns (bool) {
        return IChannel(TRUSTED_ORMP).dones(_messageId);
    }
}

