// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.6.0;
import "./SafeMathChainlink.sol";
import "./FluxAggregator.sol";
import "./H2SO.sol";

contract H2SOFA is FluxAggregator, H2SO {
    using SafeMathChainlink for uint256;

    constructor(
        address link,
        uint128 linkPaymentAmount,
        uint32 timeout,
        address validator,
        int256 minSubmissionValue,
        int256 maxSubmissionValue,
        uint8 decimals,
        string memory description
    )
        public
        FluxAggregator(
            link,
            linkPaymentAmount,
            timeout,
            validator,
            minSubmissionValue,
            maxSubmissionValue,
            decimals,
            description
        )
    {}

    function submitWithQuote(
        uint256 quoteValue,
        uint256 quoteSignedTimestamp,
        uint256 quoteValidFromTimestamp,
        uint256 quoteDurationSeconds,
        bytes calldata signedQuote
    )
        external
        validQuote(
            quoteValue,
            quoteSignedTimestamp,
            quoteValidFromTimestamp,
            quoteDurationSeconds,
            signedQuote
        )
    {
        require(quoteValue <= 2**255 - 1, "H2SOFA: Quote overflow");
        // The function below is needed so that the stack size isn't exceeded.
        _submitWithQuote(quoteValue);
    }

    function quoteIdentifier() public view override returns (bytes32) {
        return keccak256(abi.encode(description));
    }

    function _submitWithQuote(uint256 quoteValue) private {
        uint256 roundId = latestRoundId.add(1);
        submitInternal(roundId, int256(quoteValue), false);
    }
}

