// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library StringLib {
	// Taken from: 
	// https://stackoverflow.com/questions/47129173/how-to-convert-uint-to-string-in-solidity
	function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

	function strToB32(string memory s) internal pure returns (bytes32 len, bytes32 b1, bytes32 b2) {
		bytes memory t = bytes(s);
		assembly {
			len := mload(s)
			b1 := mload(add(s, 32))
		}
		if (t.length >= 16) {
			assembly {
				b2 := mload(add(s, 64))
			}
		} else {
			b2 = 0;
		}
	}

	function b32ToStr(bytes32 len, bytes32 b1, bytes32 b2, uint256 maxLen) internal pure returns (string memory str) {
		require(maxLen <= 64, "maxLen");
		bytes memory t;
		uint256 l = uint256(len);
		if (l > maxLen) {
			len = bytes32(maxLen);
		}
		assembly {
			mstore(t, len)
			mstore(add(t, 32), b1)
		}
		if (uint256(len) >= 16) {
			assembly {
				mstore(add(t, 64), b2)
			}
		}
		str = string(t);
	}
}
