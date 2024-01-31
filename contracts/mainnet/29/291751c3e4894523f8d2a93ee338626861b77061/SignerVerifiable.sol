// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

contract SignerVerifiable {

    mapping(address => uint256) private nonces;

    function getMessageHash(
        address _player,
        uint _amount,
        string calldata _message,
        string calldata _battle_id,
        uint _deadline,
        address _erc20_token, 
        address _player_referral_address
    ) public view returns (bytes32) {
        return keccak256(abi.encodePacked(nonces[_player], _player, _amount, _message, _battle_id, _deadline, _erc20_token, _player_referral_address));
    }

    function decodeSignature(
        address _player,
        uint _amount,
        string calldata _message,
        string calldata _battle_id,
        uint256 _deadline,
        address _erc20_token,
        address _player_referral_address,
        bytes calldata signature
    ) internal returns (address) {
        address decoded_signer;
        {
            bytes32 messageHash = getMessageHash(_player, _amount, _message, _battle_id, _deadline, _erc20_token, _player_referral_address);
            bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

            decoded_signer = recoverSigner(ethSignedMessageHash, signature);

            require(block.timestamp < _deadline, "Transaction expired");
            require(decoded_signer != address(0), "Error: invalid signer");
        }

        unchecked {
            ++nonces[_player];
        }

        return decoded_signer;
    }

    // INTERNAL FUNCTIONS

    function getEthSignedMessageHash(bytes32 _messageHash)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
            );
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes calldata _signature)
        internal
        pure
        returns (address)
    {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig)
        internal
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}

