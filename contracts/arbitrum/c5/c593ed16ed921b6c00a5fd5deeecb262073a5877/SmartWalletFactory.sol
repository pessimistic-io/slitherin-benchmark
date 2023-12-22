// SPDX-License-Identifier: AGPL-3.0-or-later
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

import "./SmartWallet.sol";
import "./ISmartWalletFactory.sol";
import "./Clones.sol";
import "./Ownable.sol";

contract SmartWalletFactory is ISmartWalletFactory {
	address public immutable smartWalletImplementation;
	address public immutable dispatcher;
  
  constructor(address _smartWalletImplementation, address _dispatcher) {    
    smartWalletImplementation = _smartWalletImplementation;
    dispatcher = _dispatcher;
  }

  function _build(address creator, uint96 seed) internal returns (address smartWallet) {
		bytes32 salt = keccak256(abi.encode(creator, seed));
    address implementation = smartWalletImplementation;
    assembly {
        // Cleans the upper 96 bits of the `implementation` word, then packs the first 3 bytes
        // of the `implementation` address with the bytecode before the address.
        mstore(0x00, or(shr(0xe8, shl(0x60, implementation)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
        // Packs the remaining 17 bytes of `implementation` with the bytecode after the address.
        mstore(0x20, or(shl(0x78, implementation), 0x5af43d82803e903d91602b57fd5bf3))
        smartWallet := create2(0, 0x09, 0x37, salt)
    }
    if (smartWallet != address(0)) {
      emit SmartWalletCreated(smartWallet, creator, seed);
    }
	}

	function build(address creator, uint96 seed) external returns (address smartWallet) {
    smartWallet = _build(creator, seed);
    if (smartWallet == address(0)) {
      smartWallet = getSmartWalletAddress(creator, seed);
      // EXTCODELENGTH may not access address with no code for eip-4337 validation
      // but wallet never exist on initCode validation, so this code will be never executed in that case
      require(walletExists(smartWallet), "ERC1167: create2 failed");
    } else {
      SmartWallet(payable(smartWallet)).init(creator, dispatcher, bytes20(0), new bytes(0));
    }
	}

	function buildAndExec(address creator, uint96 seed, bytes20 target, bytes calldata data) external payable returns (bytes memory response) {
		SmartWallet smartWallet = SmartWallet(payable(_build(creator, seed)));
    require(address(smartWallet) != address(0), "ERC1167: create2 failed");
		response = smartWallet.init{ value: msg.value }(creator, dispatcher, target, data);
	}

	function getSmartWalletAddress(address usr, uint96 seed) public view returns (address) {
		bytes32 salt = keccak256(abi.encode(usr, seed));
		return Clones.predictDeterministicAddress(smartWalletImplementation, salt);
	}

  function walletExists(address smartWallet) private view returns (bool) {
    return smartWallet.code.length > 2;
  }

  function findNewSmartWalletAddress(address user, uint96 initialSeed) external view returns (address smartWallet, uint96 seed) {
		seed = initialSeed;
    do {
      seed = seed + 1;
      smartWallet = getSmartWalletAddress(user,  seed);
    } while(walletExists(smartWallet));
	}

  function getWalletImplementation(address smartWallet) external view returns (address impl) {
    bytes memory code = smartWallet.code;
    require(code.length == 45, "ERC1167: wrong clone codesize");
    // pad code to 64 bytes and position implementation address at lower 20 bytes of word 0
    code = bytes.concat(new bytes(2), code, new bytes(17));
    (uint word0, uint word1) = abi.decode(code, (uint, uint));
    impl = address(uint160(word0));
    uint otherBytes = (word0 >> 160) | word1;
    // check that rest of the code matches ERC-1167 standart
    require(otherBytes == 0x5af43d82803e903d91602b57fd5bf300000000000000363d3d373d3d3d363d73, 
      "ERC1167: wrong clone bytes");
  }
}

