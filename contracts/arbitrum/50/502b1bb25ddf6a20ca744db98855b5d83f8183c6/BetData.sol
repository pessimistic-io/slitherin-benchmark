// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ECDSA.sol";
// For debugging only



/**
 * @title BetData
 * @author Deepp Dev Team
 * @notice Central definition for what a bet is with utilities to make/check etc.
 */
library BetData {

    uint256 internal constant ODDS_PRECISION = 1e10;
    uint256 private constant MAX_ODDS = 1e3;

    struct Bet {
        bytes32 marketHash;
        address token;
        uint256 amount;
        uint256 decimalOdds;
        uint256 expiry;
        address owner;
    }

    struct BetSettleResult {
            address better;
            address tokenAdd;
            uint256 paidToBetter;
            uint256 paidToLP;
            uint256 paidToFee;
    }

    /**
     * @notice Checks the parameters of a bet to see if they are valid.
     * @param bet The bet to check.
     * @return string A status string in UPPER_SNAKE_CASE.
     *         It will return "OK" if everything checks out.
     */
    function getParamValidity(Bet memory bet)
        internal
        view
        returns (string memory)
    {
        if (bet.amount == 0) {return "BET_AMOUNT_ZERO";}
        if (bet.decimalOdds <= ODDS_PRECISION || bet.decimalOdds > ODDS_PRECISION * MAX_ODDS) {
            return "INVALID_DECIMAL_ODDS";
        }
        if (bet.expiry < block.timestamp) {return "BET_EXPIRED";}
        if (bet.token == address(0)) {return "INVALID_TOKEN";}
        return "OK";
    }

    /**
     * @notice Checks the signature of a bet to see if it was signed by
     *         a given signer.
     * @param bet The bet to check.
     * @param signature The signature to compare to the signer.
     * @param signer The signer to compare to the signature.
     * @return bool True if the signature matches, false otherwise.
     */
    function checkSignature(
        Bet memory bet,
        bytes calldata signature,
        address signer
    )
        internal
        pure
        returns (bool)
    {
        return checkHashSignature(getBetHash(bet), signature, signer);
    }

    /**
     * @notice Checks the signature of a data hash to see if it was signed by
     *         a given signer.
     * @param dataHash The data to check.
     * @param signature The signature to compare to the signer.
     * @param signer The signer to compare to the signature.
     * @return bool True if the signature matches, false otherwise.
     */
    function checkHashSignature(
        bytes32 dataHash,
        bytes calldata signature,
        address signer
    )
        internal
        pure
        returns (bool)
    {
        bytes32 signedMsgHash = ECDSA.toEthSignedMessageHash(dataHash);
        return ECDSA.recover(signedMsgHash, signature) == signer;
    }

    /**
     * @notice Computes the hash of a bet. Packs the arguments in order
     *         of the Bet struct.
     * @param bet The Bet to compute the hash of.
     * @return bytes32 The calculated hash of of the bet.
     */
    function getBetHash(Bet memory bet) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                bet.marketHash,
                bet.token,
                bet.amount,
                bet.decimalOdds,
                bet.expiry,
                bet.owner
            )
        );
    }

    /**
     * @notice Logs the content of a bet to the Hardhat console log.
     * @param bet The Bet to log the content of.
     */
    function logBet(Bet storage bet) internal view {








    }
}

