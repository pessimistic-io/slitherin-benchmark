// SPDX-License-Identifier: AGPL-3.0-or-later
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
import "./SmartWalletStorage.sol";
import "./ISmartWallet.sol";
import "./IDispatcher.sol";
import "./ISmartWalletRegistry.sol";
import "./IScript.sol";

abstract contract ScriptsBase is SmartWalletStorage, IScript {
	address public immutable scriptAddress;

  event CallStart(bytes32 indexed selectorAndType, address indexed wallet, address indexed sender, uint value, bytes data) anonymous;
  event CallEnd(bytes32 indexed selectorAndType, address indexed wallet) anonymous;

	constructor() {
		scriptAddress = address(this);
	}

  modifier logged() {
    uint value;
    assembly ("memory-safe") {
      value := callvalue() // get msg.value without making function payable
    }
		ScriptsBase(scriptAddress).logCallStart(msg.sig, msg.sender, value, msg.data);
		_;
    ScriptsBase(scriptAddress).logCallEnd(msg.sig);
	}

	modifier delegated() {
    assert(address(this) != scriptAddress); // delegation required
		_;
	}

	modifier direct() {
    assert(address(this) == scriptAddress); // delegation denied
		_;
	}

	modifier useDispatcher(address dispatcher) {
		address previousDispatcher = $dispatcher;
		$dispatcher = address(dispatcher);
		_;
		$dispatcher = previousDispatcher;
	}

  function logCallStart(bytes4 selector, address sender, uint value, bytes calldata data) external direct {
    bytes32 selectorAndType = bytes32(abi.encodePacked(selector, "CallStart"));
    emit CallStart(selectorAndType, msg.sender, sender, value, data);
  }

  function logCallEnd(bytes4 selector) external direct {
    bytes32 selectorAndType = bytes32(abi.encodePacked(selector, "CallEnd"));
    emit CallEnd(selectorAndType, msg.sender);
  }

  function smartWallet() internal view returns (ISmartWallet) {
    return ISmartWallet(address(this));
  }

  function smartWalletRegistry() internal view returns (ISmartWalletRegistry) {
    return ISmartWalletRegistry(smartWallet().registry());
  }

  function originalDispatcher() internal view returns (IDispatcher) {
    return IDispatcher(smartWalletRegistry().dispatcher());
  }
}

