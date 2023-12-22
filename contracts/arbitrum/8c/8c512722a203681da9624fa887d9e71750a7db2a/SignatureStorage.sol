// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./Ownable.sol";

import {IValidSigner} from "./IValidSigner.sol";
import {IGnosis} from "./IGnosis.sol";

contract SignatureStorage is Ownable {
	bytes4 public constant ERC1257_MAGICVALUE = 0x1626ba7e;
	bytes4 public constant GNOSIS_MAGICVALUE = 0x20c13b0b;

	bytes32 public HASH;
	string public disclaimer;

	mapping(address => bool) public hasSigned;

	event Signed(address indexed user);

	constructor(bytes32 _hash) Ownable(msg.sender) {
		HASH = _hash;
	}

	function submitSignature(bytes32 _hash, bytes memory _signature) external returns (bool) {
		require(_hash == HASH, "Improper message");
		require(checkSignature(_hash, _signature, msg.sender), "invalid sig");
		hasSigned[msg.sender] = true;
		emit Signed(msg.sender);
	}

	function checkSignature(bytes32 _hash, bytes memory _signature, address _for) public view returns (bool) {
		if (isContract(_for)) {
			return checkGnosis(_hash, _signature, _for) || checkERC1271(_hash, _signature, _for);
		}
		return checkForEOA(_hash, _signature, _for);
	}

	/*
	 * HELPERS
	 */
	function extractSignature(bytes memory _signature) public pure returns (bytes32 r, bytes32 s, uint8 v) {
		require(_signature.length == 65, "Invalid signature length");

		assembly {
			// Retrieve r by loading the first 32 bytes (offset 0) of the signature
			r := mload(add(_signature, 32))

			// Retrieve s by loading the second 32 bytes (offset 32) of the signature
			s := mload(add(_signature, 64))

			// Retrieve v by loading the byte (offset 64) following the signature
			v := byte(0, mload(add(_signature, 96)))
		}
	}

	function convertBytes32ToBytes(bytes32 data) public pure returns (bytes memory) {
		bytes memory result = new bytes(32);

		assembly {
			mstore(add(result, 32), data)
		}

		return result;
	}

	function checkForEOA(bytes32 hash, bytes memory signature, address _for) public view returns (bool) {
		(bytes32 r, bytes32 s, uint8 v) = extractSignature(signature);
		address signer = ecrecover(hash, v, r, s);
		return signer == _for;
	}

	function checkGnosis(bytes32 hash, bytes memory signature, address _for) public view returns (bool) {
		bytes memory hashInBytes = convertBytes32ToBytes(hash);
		try IGnosis(_for).isValidSignature(hashInBytes, signature) returns (bytes4 val) {
			return val == GNOSIS_MAGICVALUE;
		} catch {
			return false;
		}
	}

	function checkERC1271(bytes32 hash, bytes memory signature, address _for) public view returns (bool) {
		try IValidSigner(_for).isValidSignature(hash, signature) returns (bytes4 val) {
			return val == ERC1257_MAGICVALUE;
		} catch {
			return false;
		}
	}

	function isContract(address _address) public view returns (bool) {
		uint256 codeSize;
		assembly {
			codeSize := extcodesize(_address)
		}
		return codeSize > 0;
	}

	// Hmmm....
	function canSignFor(address _user) public view returns (bool) {
		if (_user == msg.sender) return true;

		return false;
	}

	function setHash(bytes32 _hash) external onlyOwner {
		HASH = _hash;
	}

	function setDisclaimer(string calldata _newDisclaimer) external onlyOwner {
		disclaimer = _newDisclaimer;
	}
}

