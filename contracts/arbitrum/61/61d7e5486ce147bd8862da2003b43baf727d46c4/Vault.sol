// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IEIP3009Token} from "./IEIP3009Token.sol";
import {     IGelato1BalanceCCTPReceiver } from "./IGelato1BalanceCCTPReceiver.sol";

contract Vault {
    constructor(IEIP3009Token _token) {
        _token.approve(msg.sender, type(uint256).max);
    }
}

function computeVaultAddress(
    address _owner,
    IEIP3009Token _token,
    IGelato1BalanceCCTPReceiver _gelato1BalanceReceiver
) pure returns (address) {
    bytes32 hashed = keccak256(
        abi.encodePacked(
            bytes1(0xff),
            _gelato1BalanceReceiver,
            keccak256(abi.encodePacked(_owner)),
            keccak256(
                abi.encodePacked(type(Vault).creationCode, abi.encode(_token))
            )
        )
    );
    return address(uint160(uint(hashed)));
}

