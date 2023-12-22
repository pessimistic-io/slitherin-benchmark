// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Copyright (C) 2017 DappHub, LLC
// Copyright (C) 2022 Dai Foundation
// Copyright (C) 2023 VALK
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.18;

import "./ISmartWallet.sol";
import "./SmartWalletStorage.sol";
import { Account, OWNED_SMART_WALLET_ACCOUNT } from "./Account.sol";
import "./IERC721Receiver.sol";
import "./DispatchLib.sol";

contract SmartWallet is ISmartWallet, SmartWalletStorage {
	address public immutable registry;

	constructor(address _registry) {
		registry = _registry;
	}

	function init(
		address _owner,
		address _dispatcher,
		bytes20 target,
		bytes calldata data
	) external payable returns (bytes memory response) {
		require($owner == address(0), "SW: already initialized");

		$owner = _owner;
		emit SW_SetOwner(_owner);
    
		$dispatcher = _dispatcher;
		emit SW_SetDispatcher(_dispatcher);

		if (target == bytes20(0)) {
			return new bytes(0);
		}

		return _exec(_owner, _dispatcher, target, data);
	}

	function owner() external view returns (address) {
		return $owner;
	}

	function dispatcher() external view returns (address) {
		return $dispatcher;
	}

	function setOwner(address _owner) external {
		require(msg.sender == $owner, "SW: set owner not by owner");
		$owner = _owner;
		emit SW_SetOwner(_owner);
	}

	function setDispatcher(address _dispatcher) external {
		require(msg.sender == $owner, "SW: set dispatcher not by owner");
		$dispatcher = _dispatcher;
		emit SW_SetDispatcher(_dispatcher);
	}

	function delegatecall(address target, bytes memory data) internal returns (bytes memory response) {
		assembly {
			let succeeded := delegatecall(gas(), target, add(data, 0x20), mload(data), 0, 0)
			let size := returndatasize()

			response := mload(0x40)
			mstore(0x40, add(response, and(add(add(size, 0x20), 0x1f), not(0x1f))))
			mstore(response, size)
			returndatacopy(add(response, 0x20), 0, size)

			switch succeeded
			case 0 {
				revert(add(response, 0x20), size)
			}
		}
	}

  function _exec(address sender, address _dispatcher, bytes20 target, bytes calldata data) internal returns (bytes memory response) {
		require(address(target) != address(this), "SW: cannot exec self");
    require(target != bytes20(0), "SW: target required");
    bytes4 selector = bytes4(data[0:4]);
    address dispatchedTarget = address(target);

		if (_dispatcher == address(0)) {
			require(sender == $owner || sender == address(this), "SW: exec not authorized");
		} else {
			dispatchedTarget = DispatchLib.dispatch({
        dispatcher: _dispatcher,
				source: sender,
        wallet: address(this),
				executor: Account(address(this), OWNED_SMART_WALLET_ACCOUNT),
				target: target,
				selector: selector
      });
		}
    
    emit SW_Exec(sender, selector, dispatchedTarget, target, msg.value);
		return delegatecall(dispatchedTarget, data);
	}

	function exec(bytes20 target, bytes calldata data) external payable returns (bytes memory response) {
		return _exec(msg.sender, $dispatcher, target, data);
	}

	receive() external payable {
		emit SW_Fallback(msg.sender, msg.sig, msg.value);
	}

	fallback(bytes calldata data) external payable returns (bytes memory result) {
		address target;
		if (msg.sig != 0x00000000) {
			address _dispatcher = $dispatcher;

			if (_dispatcher != address(0)) {
				target = DispatchLib.dispatch({
          dispatcher: _dispatcher,
					source: msg.sender,
          wallet: address(this),
					executor: Account(address(this), OWNED_SMART_WALLET_ACCOUNT),
					target: bytes20(address(this)),
					selector: msg.sig
        });
        emit SW_ExecDirect(msg.sender, msg.sig, target, msg.value);
        return delegatecall(target, data);
			}
		}
		
    emit SW_Fallback(msg.sender, msg.sig, msg.value);
    return bytes.concat(bytes32(msg.sig)); // answer to onERCXXXReceived and similar
	}
}

