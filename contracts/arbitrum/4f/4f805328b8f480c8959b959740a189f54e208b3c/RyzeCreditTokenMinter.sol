// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./Ownable.sol";
import "./ECDSA.sol";

import "./RyzeCreditToken.sol";

/**
 * @title Free Credit Token Minter
 * @author Balance Capital
 */
contract RyzeCreditTokenMinter is Ownable {
    using ECDSA for bytes32;

    event SignatureVerifierSet(address indexed verifier);
    event DailyMintLimitSet(uint256 indexed tokenId, uint256 dailyMintLimit);
    event Claimed(
        address indexed to,
        uint256 indexed tokenId,
        uint256 amount,
        bytes signature
    );

    struct HourlyMint {
        uint256 timestampFrom;
        uint256 timestampTo;
        uint256 amount;
    }

    RyzeCreditToken public ryzeCreditToken;

    // The claim signature verifier address
    address public signatureVerifier;

    mapping(uint256 => HourlyMint[]) public hourlyMintsByTokenId;
    // 24 hours mint limit
    mapping(uint256 => uint256) public dailyMintLimit;
    mapping(bytes => bool) public isSignatureUsed;

    // user => total claimed amount
    mapping(address => uint256) public userTotalClaimed;

    constructor(address _ryzeCreditToken) {
        ryzeCreditToken = RyzeCreditToken(_ryzeCreditToken);
    }

    /// @notice Set signature verifier address
    /// @dev Only owner
    /// @param _verifier The signature verifier address
    function setSignatureVerifier(address _verifier) external onlyOwner {
        signatureVerifier = _verifier;

        emit SignatureVerifierSet(_verifier);
    }

    /// @notice Set daily mint limit
    /// @dev Only owner
    /// @param _dailyMintLimit The daily mint limit
    function setDailyMintLimit(
        uint256 _tokenId,
        uint256 _dailyMintLimit
    ) external onlyOwner {
        dailyMintLimit[_tokenId] = _dailyMintLimit;
        emit DailyMintLimitSet(_tokenId, _dailyMintLimit);
    }

    /// @notice Claim free credit tokens
    /// @param _to The recipient address
    /// @param _tokenId The token ID
    /// @param _amount The token amount to claim
    /// @param _generatedAt The timestamp of signature generation
    /// @param _signature The claim signature
    function claim(
        address _to,
        uint256 _tokenId,
        uint256 _amount,
        uint256 _userTotalClaimed,
        uint256 _generatedAt,
        bytes memory _signature
    ) external {
        require(
            lastDayMint(_tokenId) + _amount <= dailyMintLimit[_tokenId],
            "Daily mint limit"
        );
        require(!isSignatureUsed[_signature], "Signature already used");
        require(userTotalClaimed[_to] == _userTotalClaimed, "invalid claimed amount");

        // verify the signature
        bytes32 payloadHash = keccak256(
            abi.encodePacked(_to, _tokenId, _amount, _userTotalClaimed, _generatedAt)
        );
        require(
            payloadHash.toEthSignedMessageHash().recover(_signature) ==
                signatureVerifier,
            "Invalid claim signature"
        );

        isSignatureUsed[_signature] = true;
        userTotalClaimed[_to] += _amount;
        _updateHourlyMint(_tokenId, _amount);

        ryzeCreditToken.mint(_to, _tokenId, _amount);

        emit Claimed(_to, _tokenId, _amount, _signature);
    }

    /// @notice Returns last 24 hours mint amount
    /// @return amount Last 24 hours mint amount
    function lastDayMint(uint256 _tokenId) public view returns (uint amount) {
        HourlyMint[] memory hourlyMints = hourlyMintsByTokenId[_tokenId];

        if (hourlyMints.length == 0) return 0;

        uint256 max = 0;
        if (hourlyMints.length >= 24) max = hourlyMints.length - 24;

        uint256 to = block.timestamp;
        uint256 from = to - 24 hours;
        for (uint256 i = max; i < hourlyMints.length; ++i) {
            if (
                hourlyMints[i].timestampFrom >= from &&
                hourlyMints[i].timestampFrom <= to
            ) {
                amount += hourlyMints[i].amount;
            }
        }

        return amount;
    }

    /// @notice Record hourly mint
    function _updateHourlyMint(uint256 tokenId, uint amount) internal {
        HourlyMint[] storage hourlyMints = hourlyMintsByTokenId[tokenId];

        uint256 currentTimestamp = block.timestamp;
        uint256 length = hourlyMints.length;
        if (length == 0) {
            hourlyMints.push(
                HourlyMint({
                    timestampFrom: currentTimestamp,
                    timestampTo: currentTimestamp + 1 hours,
                    amount: amount
                })
            );
            return;
        }

        HourlyMint storage lastHourlyMint = hourlyMints[length - 1];
        // update in existing interval
        if (
            lastHourlyMint.timestampFrom < currentTimestamp &&
            lastHourlyMint.timestampTo >= currentTimestamp
        ) {
            lastHourlyMint.amount += amount;
        } else {
            // create next interval if its continuous
            if (currentTimestamp <= lastHourlyMint.timestampTo + 1 hours) {
                hourlyMints.push(
                    HourlyMint({
                        timestampFrom: lastHourlyMint.timestampTo,
                        timestampTo: lastHourlyMint.timestampTo + 1 hours,
                        amount: amount
                    })
                );
            } else {
                hourlyMints.push(
                    HourlyMint({
                        timestampFrom: currentTimestamp,
                        timestampTo: currentTimestamp + 1 hours,
                        amount: amount
                    })
                );
            }
        }
    }
}

