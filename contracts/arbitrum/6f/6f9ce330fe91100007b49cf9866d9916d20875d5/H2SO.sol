// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.6.0;
import "./Owned.sol";
import "./Signature.sol";

abstract contract H2SO is Signature, Owned {
    address public quoteSigner;
    uint256 public lastQuoteTimestamp;

    event SetQuoteSigner(address indexed oldSigner, address indexed newSigner);
    event UnsetQuoteSigner(address indexed oldSigner);

    modifier validQuote(
        uint256 quoteValue,
        uint256 quoteSignedTimestamp,
        uint256 quoteValidFromTimestamp,
        uint256 quoteDurationSeconds,
        bytes memory signedQuote
    ) {
        require(
            quoteSignedTimestamp > lastQuoteTimestamp,
            "H2SO: Quote is old"
        );
        require(
            block.timestamp >= quoteValidFromTimestamp,
            "H2SO: Quote is not valid yet"
        );
        require(
            block.timestamp <= quoteValidFromTimestamp + quoteDurationSeconds,
            "H2SO: Quote has expired"
        );
        bytes32 quote = keccak256(
            abi.encode(
                quoteValue,
                getChainId(),
                quoteSignedTimestamp,
                quoteValidFromTimestamp,
                quoteDurationSeconds,
                quoteIdentifier()
            )
        );
        address untrustedSigner = getSignatureAddress(
            encodeERC191(quote),
            signedQuote
        );
        require(untrustedSigner == quoteSigner, "H2SO: Invalid Signature");
        lastQuoteTimestamp = quoteSignedTimestamp;
        _;
    }

    function setQuoteSigner(address newSigner) external onlyOwner {
        setQuoteSignerInternal(newSigner);
    }

    /**
     * @dev Unique identifier for the oracle being quoted.
     */
    function quoteIdentifier() public view virtual returns (bytes32);

    function setQuoteSignerInternal(address newSigner) internal {
        address oldSigner = quoteSigner;
        quoteSigner = newSigner;
        if (newSigner == address(0)) {
            emit UnsetQuoteSigner(oldSigner);
            return;
        }
        emit SetQuoteSigner(oldSigner, newSigner);
    }

    function getChainId() private view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }
}

