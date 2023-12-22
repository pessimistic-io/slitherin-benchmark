// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Base64.sol";
import "./Strings.sol";
import "./BigNumbers.sol";

// errors
error CTAThresholdOutOfBoundaries(
    uint256 revealThreshold,
    uint256 minRevealThreshold,
    uint256 maxRevealThreshold
);
error CTAInconsistentTLPIterations(uint256 timeLockPuzzleIterations);
error CTATimeToRevealOutOfBoundaries(
    uint256 timeToAllowReveal,
    uint256 minTimeToReveal,
    uint256 maxTimeToReveal
);
error CTAInvalidVerificators(
    uint256 verificatorsBytesLength,
    uint256 revealThreshold
);
error CTAInvalidGenerator();
error CTAInvalidShare();
error CTACannotMintExistentLeaderboard();
error CTACanOnlyJoinLeaderboardThatIsNotRevealed();
error CTACanOnlyJoinLeaderboardThatIsNotReadyToReveal();
error CTACanOnlyRevealLeaderboardThatIsNotRevealed();
error CTACannotRevealLeaderboardThatIsNotReadyToReveal();
error CTACannotRevealNonexistentLeaderboard();
error CTAOnlyHuntersCanReveal();
error CTATooSoonToRevealLeaderboard();
error CTASecretIsNotConsistentWithHash();
error CTAEncryptionKeyIsNotConsistentWithTLP();
error ERC721MetadataURIQueryForNonexistentToken();
error CTACannotJoinOrRevealNonexistentLeaderboard();
error CTAHunterAlreadyListed();
error CTANonexistentLeaderboard(uint256 tokenId);
error CTAPageRankNotConverged();

struct Leaderboard {
    bytes32 hash;
    uint256 secret;
    uint32 revealThreshold;
    uint64 mintTimestamp;
    uint64 timeToAllowReveal;
    Share[] shares;
    bytes generator;
    bytes blindingGenerator;
    bytes[] verificators;
    bytes timeLockedKey;
    bytes timeLockPuzzleModulus;
    bytes timeLockPuzzleBase;
    uint256 timeLockPuzzleIterations;
    bytes encryptedSecretCiphertext;
    bytes encryptedSecretIv;
}
struct GetLeaderboardQueryResult {
    Leaderboard leaderboard;
    bool revealed;
}

struct Share {
    address hunter;
    bytes index;
    bytes evaluation;
    uint256 timeWhenJoined;
}

struct JoinData {
    bytes32 secretHash;
    bytes indexBytes;
    bytes shareBytes;
    bytes blindingShareBytes;
}

struct MintData {
    JoinData joinData;
    bytes generatorBytes;
    bytes blindingGeneratorBytes;
    bytes[] verificatorsBytes;
    uint32 revealThreshold;
    uint256 timeToAllowReveal;
    bytes timeLockedKeyBytes;
    bytes timeLockPuzzleModulusBytes;
    bytes timeLockPuzzleBaseBytes;
    uint256 timeLockPuzzleIterations;
    bytes ciphertextBytes;
    bytes ivBytes;
}

struct RevealData {
    JoinData joinData;
    bytes[] interpolationInverses;
}

struct HunterLeaderboardIds {
    uint256[] tokenIds;
    uint256 publicSupply;
    uint256 privateSupply;
}

library Utils {
    using BigNumbers for *;
    using Utils for Leaderboard;

    // safe prime in RFC3526 https://datatracker.ietf.org/doc/rfc3526/
    bytes public constant COEFF_PRIME_BYTES =
        hex"FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF";

    /**
     * @notice CTA leaderboard fetching common functinoality
     * @dev gets a leaderboard making sure it is valid for the given parameters
     * @param joinData Data including secretHash, indexBytes, shareBytes & blindingShareBytes
     * @param tokenIdToLeaderboardMap Token ID to leaderboard mapping\
     * @param hashToLeaderboardTokenIdMap Hash to token ID mapping
     */
    function checkAndGetExistentLeaderboard(
        JoinData memory joinData,
        mapping(uint256 => Leaderboard) storage tokenIdToLeaderboardMap,
        mapping(bytes32 => uint256) storage hashToLeaderboardTokenIdMap
    ) external view returns (Leaderboard storage) {
        Leaderboard storage _leaderboard = tokenIdToLeaderboardMap[
            hashToLeaderboardTokenIdMap[joinData.secretHash]
        ];
        bool leaderboardExists = _leaderboard.shares.length >= 1;

        if (!leaderboardExists) {
            revert CTACannotJoinOrRevealNonexistentLeaderboard();
        }

        bool isHunter = verifyIfHunterIsOnLeaderboard(_leaderboard);

        if (isHunter) {
            revert CTAHunterAlreadyListed();
        }

        bool validShare = vsssVerifyShare(
            joinData,
            _leaderboard.generator,
            _leaderboard.blindingGenerator,
            _leaderboard.verificators
        );

        if (!validShare) {
            revert CTAInvalidShare();
        }

        return _leaderboard;
    }

    function verifyIfHunterIsOnLeaderboard(
        Leaderboard storage leaderboard_
    ) public view returns (bool isHunter) {
        //checking if the hunter is already listed on the leaderboard
        for (uint256 i = 0; i < leaderboard_.shares.length; i++) {
            if (leaderboard_.shares[i].hunter == msg.sender) {
                isHunter = true;
                break;
            }
        }

        return isHunter;
    }

    /**
     * @notice VSSS verification
     * @dev verifies a share in a VSSS scheme using the verificators
     * @param joinData Data including indexBytes, shareBytes and blindingShareBytes
     * @param generatorBytes bytes memory
     * @param blindingGeneratorBytes bytes memory
     * @param verificatorsBytes bytes[] memory
     * @return bool
     */
    function vsssVerifyShare(
        JoinData memory joinData,
        bytes memory generatorBytes,
        bytes memory blindingGeneratorBytes,
        bytes[] memory verificatorsBytes
    ) public view returns (bool) {
        BigNumber memory coeffPrime = BigNumbers.init(COEFF_PRIME_BYTES, false);

        // shr is inplace
        BigNumber memory exponentPrime = BigNumbers
            .init(COEFF_PRIME_BYTES, false)
            .shr(1);

        BigNumber memory index = BigNumbers.init(joinData.indexBytes, false);
        BigNumber memory evaluation = BigNumbers.init(
            joinData.shareBytes,
            false
        );
        BigNumber memory blindingEvaluation = BigNumbers.init(
            joinData.blindingShareBytes,
            false
        );
        BigNumber memory addressNum = BigNumbers.init(
            uint160(msg.sender),
            false
        );
        BigNumber memory verificatorGenerator = BigNumbers.init(
            generatorBytes,
            false
        );

        BigNumber memory blindingGenerator = BigNumbers.init(
            blindingGeneratorBytes,
            false
        );

        BigNumber[] memory verificators = new BigNumber[](
            verificatorsBytes.length
        );

        for (uint256 i = 0; i < verificators.length; i++) {
            verificators[i] = BigNumbers.init(verificatorsBytes[i], false);
        }

        if (!index.eq(addressNum.mod(coeffPrime))) {
            return false;
        } else {
            BigNumber memory verification = calculateVerification(
                verificators,
                index,
                coeffPrime,
                exponentPrime
            );
            return
                verification.eq(
                    verificatorGenerator.modexp(evaluation, coeffPrime).modmul(
                        blindingGenerator.modexp(
                            blindingEvaluation,
                            coeffPrime
                        ),
                        coeffPrime
                    )
                );
        }
    }

    /**
     * @notice VSSS verification calculation
     * @dev calculates the verification from the verificators
     * @param verificators BigNumber[] memory
     * @param index BigNumber memory
     * @param coeffPrime BigNumber memory
     * @param exponentPrime BigNumber memory
     * @return BigNumber memory
     */
    function calculateVerification(
        BigNumber[] memory verificators,
        BigNumber memory index,
        BigNumber memory coeffPrime,
        BigNumber memory exponentPrime
    ) public view returns (BigNumber memory) {
        BigNumber memory verification = BigNumbers.one();
        BigNumber memory indexPower = BigNumbers.one();
        for (uint256 i = 0; i < verificators.length; i++) {
            verification = verification.modmul(
                verificators[i].modexp(indexPower, coeffPrime),
                coeffPrime
            );
            indexPower = indexPower.modmul(index, exponentPrime);
        }
        return verification;
    }

    /**
     * @notice VSSS secret integrity validation
     * @dev uses verificator to verify integrity of secret
     * @param secret uint256 memory
     * @param blindingSecretBytes bytes memory
     * @param firstVerificatorBytes bytes memory
     * @param generatorBytes bytes memory
     * @param blindingGeneratorBytes bytes memory
     * @return bool
     */
    function vsssValidateSecretIntegrity(
        uint256 secret,
        bytes memory blindingSecretBytes,
        bytes memory firstVerificatorBytes,
        bytes memory generatorBytes,
        bytes memory blindingGeneratorBytes
    ) external view returns (bool) {
        BigNumber memory secretBN = BigNumbers.init(secret, false);
        BigNumber memory blindingSecret = BigNumbers.init(
            blindingSecretBytes,
            false
        );
        BigNumber memory firstVerificator = BigNumbers.init(
            firstVerificatorBytes,
            false
        );
        BigNumber memory generator = BigNumbers.init(generatorBytes, false);
        BigNumber memory blindingGenerator = BigNumbers.init(
            blindingGeneratorBytes,
            false
        );
        BigNumber memory coeffPrime = BigNumbers.init(COEFF_PRIME_BYTES, false);

        return
            firstVerificator.eq(
                generator.modexp(secretBN, coeffPrime).modmul(
                    blindingGenerator.modexp(blindingSecret, coeffPrime),
                    coeffPrime
                )
            );
    }

    /**
     * @notice VSSS generator verification
     * @dev verifies if the generator in a VSSS has the expected order
     * @param generatorBytes bytes memory
     * @return bool
     */
    function vsssVerifyGeneratorOrder(
        bytes memory generatorBytes
    ) external view returns (bool) {
        BigNumber memory coeffPrime = BigNumbers.init(COEFF_PRIME_BYTES, false);

        // shr is inplace
        BigNumber memory exponentPrime = BigNumbers
            .init(COEFF_PRIME_BYTES, false)
            .shr(1);

        BigNumber memory generator = BigNumbers.init(generatorBytes, false);

        if (
            generator.mod(coeffPrime).eq(BigNumbers.one()) ||
            generator.mod(coeffPrime).eq(coeffPrime.sub(BigNumbers.one()))
        ) {
            return false;
        } else {
            return
                generator.modexp(exponentPrime, coeffPrime).eq(
                    BigNumbers.one()
                );
        }
    }

    /**
     * @notice VSSS interpolation
     * @dev interpolates secret from shares
     * @param shares Share[] memory
     * @param interpolationInversesBytes bytes[] memory
     * @return BigNumber memory
     */
    function vsssInterpolate(
        Share[] memory shares,
        bytes[] memory interpolationInversesBytes
    ) external view returns (uint256) {
        BigNumber[] memory indexes = new BigNumber[](shares.length);
        BigNumber[] memory evaluations = new BigNumber[](shares.length);

        BigNumber memory coeffPrime = BigNumbers.init(COEFF_PRIME_BYTES, false);

        BigNumber[] memory interpolationInverses = new BigNumber[](
            interpolationInversesBytes.length
        );

        for (uint256 i = 0; i < shares.length; i++) {
            indexes[i] = BigNumbers.init(shares[i].index, false);
        }

        for (uint256 i = 0; i < shares.length; i++) {
            evaluations[i] = BigNumbers.init(shares[i].evaluation, false);
        }

        for (uint256 i = 0; i < interpolationInversesBytes.length; i++) {
            interpolationInverses[i] = BigNumbers.init(
                interpolationInversesBytes[i],
                false
            );
        }
        BigNumber memory secret = BigNumbers.zero();

        for (uint256 i = 0; i < indexes.length; i++) {
            BigNumber memory numerator = BigNumbers.one();
            BigNumber memory denominator = BigNumbers.one();
            for (uint256 j = 0; j < indexes.length; j++) {
                if (j != i) {
                    numerator = numerator.modmul(
                        BigNumbers.zero().sub(indexes[j]),
                        coeffPrime
                    );
                    denominator = denominator.modmul(
                        indexes[i].sub(indexes[j]),
                        coeffPrime
                    );
                }
            }
            assert(
                denominator.modinvVerify(coeffPrime, interpolationInverses[i])
            );
            secret = secret
                .add(
                    numerator
                        .modmul(interpolationInverses[i], coeffPrime)
                        .modmul(evaluations[i], coeffPrime)
                )
                .mod(coeffPrime);
        }

        return uint256(bytes32(secret.val));
    }

    /**
     * @notice TLP key integrity validation
     * @dev uses modulus factorization to verify TLP instance
     * @param keyBytes bytes memory
     * @param pBytes bytes memory
     * @param qBytes bytes memory
     * @param timeLockedKeyBytes bytes memory
     * @param timeLockPuzzleBaseBytes bytes memory
     * @param timeLockPuzzleModulusBytes bytes memory
     * @param timeLockPuzzleIterations uint256
     * @return bool
     */
    function tlpValidateKeyIntegrity(
        bytes memory keyBytes,
        bytes memory pBytes,
        bytes memory qBytes,
        bytes memory timeLockedKeyBytes,
        bytes memory timeLockPuzzleBaseBytes,
        bytes memory timeLockPuzzleModulusBytes,
        uint256 timeLockPuzzleIterations
    ) external view returns (bool) {
        BigNumber memory key = BigNumbers.init(keyBytes, false);
        BigNumber memory p = BigNumbers.init(pBytes, false);
        BigNumber memory q = BigNumbers.init(qBytes, false);
        BigNumber memory timeLockedKey = BigNumbers.init(
            timeLockedKeyBytes,
            false
        );
        BigNumber memory timeLockPuzzleBase = BigNumbers.init(
            timeLockPuzzleBaseBytes,
            false
        );
        BigNumber memory timeLockPuzzleModulus = BigNumbers.init(
            timeLockPuzzleModulusBytes,
            false
        );
        BigNumber memory timeLockPuzzleIterationsBN = BigNumbers.init(
            timeLockPuzzleIterations,
            false
        );

        // check if factorization is correct
        if (!timeLockPuzzleModulus.eq(p.mul(q))) {
            return false;
        }

        BigNumber memory phi = p.sub(BigNumbers.one()).mul(
            q.sub(BigNumbers.one())
        );

        BigNumber memory reducedExponent = BigNumbers.two().modexp(
            timeLockPuzzleIterationsBN,
            phi
        );

        // check if TLP is consistent
        return
            timeLockedKey.eq(
                timeLockPuzzleBase
                    .modexp(reducedExponent, timeLockPuzzleModulus)
                    .add(key)
            );
    }

    /* solhint-disable quotes */
    function buildMain(
        string memory id,
        bool revealed
    ) public pure returns (string memory) {
        string memory textColor = revealed ? "#5EFE34" : "white";
        string memory rectColor = revealed ? "#1E4D13" : "black";

        return
            string.concat(
                '<g><rect fill="',
                rectColor,
                '" x="0" y="0" width="350" height="350"></rect>',
                '<text font-family="Arial, Helvetica, sans-serif" y="45%" x="50%" dominant-baseline="middle" text-anchor="middle" font-size="200%" font-weight="bold" fill="',
                textColor,
                '">CTA</text>',
                '<text font-family="Arial, Helvetica, sans-serif" y="55%" x="50%" dominant-baseline="middle" text-anchor="middle" font-size="200%" font-weight="bold" fill="',
                textColor,
                '">#',
                id,
                "</text>",
                "</g>"
            );
    }

    /*
     * @notice CTA build SVG function
     * @dev building the CTA svg image from the hash
     * @param uint256 tokenId
     * @return base64 encoded svg
     */
    function buildSVG(
        uint256 tokenId,
        bool revealed
    ) public pure returns (string memory) {
        string
            memory SVG_HEADER = '<svg xmlns="http://www.w3.org/2000/svg" height="350" width="350">';
        string memory SVG_FOOTER = "</svg>";

        string memory id = Strings.toString(tokenId);
        return
            Base64.encode(
                bytes(
                    string.concat(
                        SVG_HEADER,
                        buildMain(id, revealed),
                        SVG_FOOTER
                    )
                )
            );
    }

    /* solhint-enable quotes */

    /**
     * @notice converting the hash to a string of the 10 first chars
     * @dev convertion from bytes32 to array bytes(5) then abi.encodePacked donsen't work :/ i did it manually
     * @param bytes32_ bytes32
     * @return string memory
     */
    function hashPart(bytes32 bytes32_) internal pure returns (string memory) {
        bytes memory converted = abi.encodePacked("");
        string[16] memory _base = [
            "0",
            "1",
            "2",
            "3",
            "4",
            "5",
            "6",
            "7",
            "8",
            "9",
            "a",
            "b",
            "c",
            "d",
            "e",
            "f"
        ];
        for (uint256 i = 0; i < 5; i++) {
            converted = abi.encodePacked(
                converted,
                _base[uint8(bytes32_[i]) / _base.length]
            );
            converted = abi.encodePacked(
                converted,
                _base[uint8(bytes32_[i]) % _base.length]
            );
        }
        converted = abi.encodePacked("0x", converted);
        return string(converted);
    }

    /// @notice See {Cta-tokenURI}
    function tokenURI(
        uint256 tokenId,
        mapping(uint256 => Leaderboard) storage tokenIdToLeaderboardMap
    ) external view returns (string memory) {
        //creating the svg image and encoding in base64
        Leaderboard storage _leaderboard = tokenIdToLeaderboardMap[tokenId];
        string memory encodedSVG = buildSVG(tokenId, _leaderboard.isRevealed());
        bytes32 hash = tokenIdToLeaderboardMap[tokenId].hash;
        string memory attributes = "";
        string memory hunterAddress = "";
        string memory comma = "";
        string memory _hashPart = hashPart(hash);

        /* solhint-disable quotes */
        if (_leaderboard.shares.length >= 1) {
            for (uint256 i = 0; i < _leaderboard.shares.length; i++) {
                //add hunter address to attributes
                hunterAddress = Strings.toHexString(
                    uint160(_leaderboard.shares[i].hunter),
                    20
                );
                attributes = string.concat(
                    attributes,
                    comma,
                    '{"trait_type": "',
                    Strings.toString(i),
                    '","value": "',
                    hunterAddress,
                    '"}'
                );
                comma = ",";
            }
        }

        string memory baseJson = string.concat(
            '{"name": "Capture The Alpha","description": "CTA is the first on-chain competition between alpha hunters","tokenId":"',
            Strings.toString(tokenId),
            '", "attributes" : [',
            attributes,
            ', {"trait_type": "isPrivate", "value":',
            !tokenIdToLeaderboardMap[tokenId].isRevealed() ? "true" : "false",
            '}, {"trait_type": "hash", "value": "',
            _hashPart,
            '" }],"image" : "data:image/svg+xml;base64,',
            encodedSVG,
            '"}'
        );
        /* solhint-enable quotes */

        //next step encoding for the tokenURI
        string memory jsonHeaderURI = "data:application/json;base64,";
        string memory encodedJson = string.concat(
            jsonHeaderURI,
            Base64.encode(bytes(baseJson))
        );

        //the result must be a string and not bytes data
        return encodedJson;
    }

    function isRevealed(
        Leaderboard storage leaderboard
    ) internal view returns (bool) {
        return leaderboard.secret != 0;
    }

    function getAdjacencyMatrix(
        uint256 size,
        uint256 supply,
        mapping(uint256 => Leaderboard) storage tokenIdToLeaderboardMap,
        address[] storage allHunters
    ) public view returns (int256[][] memory, uint256) {
        int256[][] memory matrix = new int256[][](size);
        for (uint256 i = 0; i < size; i++) {
            matrix[i] = new int256[](size);
        }

        uint256 publicSupply = 0;
        for (uint256 i = 1; i <= supply; i++) {
            Leaderboard storage _leaderboard = tokenIdToLeaderboardMap[i];

            // We only consider public leaderboards
            if (!_leaderboard.isRevealed()) {
                continue;
            }

            publicSupply += 1;
            address firstAddress = _leaderboard.shares[0].hunter;
            uint256 startIndex = 1;
            uint256 indexIn = getHunterIndex(
                firstAddress,
                startIndex,
                allHunters
            );
            for (uint256 j = 1; j < _leaderboard.shares.length; j++) {
                uint256 indexOut = getHunterIndex(
                    _leaderboard.shares[j].hunter,
                    startIndex,
                    allHunters
                );
                matrix[indexIn][indexOut] = matrix[indexIn][indexOut] + 1;
            }
        }

        return (matrix, publicSupply);
    }

    function getHunterIndex(
        address hunter,
        uint256 startIndex,
        address[] storage allHunters
    ) public view returns (uint256) {
        uint256 defaultIndex = 0;
        for (uint256 j = startIndex; j < allHunters.length; j++) {
            if (allHunters[j] == hunter) {
                return j;
            }
        }
        return defaultIndex;
    }
}

