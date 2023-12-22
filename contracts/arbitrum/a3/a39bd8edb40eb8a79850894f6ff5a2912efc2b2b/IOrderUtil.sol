// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IOrderUtil {
    struct Order {
        address poolAddress;
        address underlying;
        address referrer;
        uint256 validUntil;
        uint256 nonce;
        OptionLeg[] legs;
        Signature signature;
        Signature[] coSignatures;
    }

    struct OptionLeg {
        uint256 strike;
        uint256 expiration;
        bool isPut;
        int256 amount;
        int256 premium;
        uint256 fee;
    }

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    event Cancel(uint256 indexed nonce, address indexed signerWallet);

    event CancelUpTo(uint256 indexed nonce, address indexed signerWallet);

    error InvalidAdapters();
    error OrderExpired();
    error NonceTooLow();
    error NonceAlreadyUsed(uint256);
    error SenderInvalid();
    error SignatureInvalid();
    error SignerInvalid();
    error TokenKindUnknown();
    error Unauthorized();

    /**
     * @notice Validates order and returns its signatory
     * @param order Order
     */
    function processOrder(
        Order calldata order
    ) external returns (address signer, address[] memory coSigners);

    /**
     * @notice Cancel one or more open orders by nonce
     * @param nonces uint256[]
     */
    function cancel(uint256[] calldata nonces) external;

    /**
     * @notice Cancels all orders below a nonce value
     * @dev These orders can be made active by reducing the minimum nonce
     * @param minimumNonce uint256
     */
    function cancelUpTo(uint256 minimumNonce) external;

    function nonceUsed(address, uint256) external view returns (bool);

    function getSigners(
        Order calldata order
    ) external returns (address signer, address[] memory coSigners);
}

