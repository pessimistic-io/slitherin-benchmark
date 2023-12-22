// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {Bridge} from "./Struct.sol";

library Converter {

    /**
    * @dev prefix a bytes32 value with "\x19Ethereum Signed Message:" and hash the result
    */
    function ethMessageHash(bytes32 message) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32"  , message)
        );
    }

    function ethTicketHash(Bridge.TICKET memory ticket) internal pure returns (bytes32)  {
        return keccak256(abi.encodePacked(
            ticket.amount,
            ticket.dst_address,
            ticket.dst_network,
            ticket.name,
            ticket.nonce,
            ticket.origin_decimals,
            ticket.origin_hash,
            ticket.origin_network,
            ticket.src_address,
            ticket.src_hash,
            ticket.src_network,
            ticket.symbol));
    }

    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);            
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
