// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./EIP712Upgradeable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./CountersUpgradeable.sol";

import "./INomisONFT.sol";

///////////////////////////////////////////////////////////////
//  ___   __    ______   ___ __ __    ________  ______       //
// /__/\ /__/\ /_____/\ /__//_//_/\  /_______/\/_____/\      //
// \::\_\\  \ \\:::_ \ \\::\| \| \ \ \__.::._\/\::::_\/_     //
//  \:. `-\  \ \\:\ \ \ \\:.      \ \   \::\ \  \:\/___/\    //
//   \:. _    \ \\:\ \ \ \\:.\-/\  \ \  _\::\ \__\_::._\:\   //
//    \. \`-\  \ \\:\_\ \ \\. \  \  \ \/__\::\__/\ /____\:\  //
//     \__\/ \__\/ \_____\/ \__\/ \__\/\________\/ \_____\/  //
//                                                           //
///////////////////////////////////////////////////////////////

/**
 * @title NomisScore
 * @dev The NomisScore contract is an ERC721 token contract with additional functionality for managing scores.
 * @custom:security-contact info@nomis.cc
 */
contract NomisScore is
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _tokenIds;

    /*#########################
    ##        Structs        ##
    ##########################*/

    /**
     * @dev The Score struct represents a user's score.
     */
    struct Score {
        uint256 tokenId;
        uint256 updated;
        uint16 value;
    }

    /*#########################
    ##       Variables       ##
    ##########################*/

    /**
     * @notice The NomisONFT contract address.
     */
    address public nomisONFT;

    string private _baseUri;
    uint16 private _calcModelsCount;

    uint256 private _mintFee;
    uint256 private _updateFee;
    uint256 private _referralReward;

    /*#########################
    ##        Mappings       ##
    ##########################*/

    /**
     * @dev A mapping of token id to calculation model.
     */
    mapping(uint256 => uint16) public tokenIdToCalcModel;

    /**
     * @dev A mapping of token id to chain id.
     */
    mapping(uint256 => uint256) public tokenIdToChainId;

    /**
     * @dev A mapping of addresses with scoring calculation model to whitelist.
     */
    mapping(address => mapping(uint16 => bool)) public whitelist;

    /**
     * @dev A mapping of calculation model to free mint count.
     */
    mapping(uint16 => uint16) public calculationModelToFreeMintCount;

    /**
     * @dev A mapping of calculation model to mint count used.
     */
    mapping(uint16 => uint256) public calculationModelToMintCountUsed;

    /**
     * @dev A mapping of addresses, chains and calculation methods to scores.
     */
    mapping(address => mapping(uint256 => mapping(uint16 => Score)))
        private _score;

    /**
     * @dev A mapping of addresses to nonces for replay protection.
     */
    mapping(address => uint256) private _nonce;

    /**
     * @dev A mapping of addresses to referral codes (string).
     */
    mapping(address => string) private _walletToReferralCode;

    /**
     * @dev A mapping of referrer codes (bytes32) to wallets.
     */
    mapping(bytes32 => address) private _referralCodeToWallet;

    /**
     * @dev A mapping of token ids of owners who referred by referrer code.
     */
    mapping(bytes32 => uint256[]) private _referrerCodeToTokenIds;

    /**
     * @dev The individual mint fee value for each address.
     */
    mapping(address => mapping(uint16 => uint256)) private _individualMintFee;

    /**
     * @dev The individual update fee value for each address.
     */
    mapping(address => mapping(uint16 => uint256)) private _individualUpdateFee;

    /**
     * @dev The individual rewards per referral value for each address.
     */
    mapping(address => uint256) private _individualReward;

    /**
     * @dev A mapping of wallet to its token ids.
     */
    mapping(address => uint256[]) private _walletToTokenIds;

    /**
     * @dev A mapping of referred wallets to status if wallet is already rewarded.
     */
    mapping(address => bool) private _alreadyRewardedWallet;

    /*#########################
    ##        Modifiers      ##
    ##########################*/

    /**
     * @dev Modifier that checks if the passed fee is equal to the current mint fee set.
     * @param calcModel The scoring calculation model.
     * @param chainId The blockchain id in which the score was calculated.
     * Requirements:
     * The fee passed must be equal to the current mint or update fee set.
     */
    modifier equalsFee(uint16 calcModel, uint256 chainId) {
        address _wallet = msg.sender;
        uint256 _fee = msg.value;
        // check update fee

        uint256 walletUpdateFee = _individualUpdateFee[_wallet][calcModel];
        uint256 walletMintFee = _individualMintFee[_wallet][calcModel];
        Score storage scoreStruct = _score[_wallet][chainId][calcModel];

        if (scoreStruct.updated > 0) {
            require(
                (_fee == walletUpdateFee && _fee > 0) ||
                    whitelist[_wallet][calcModel] ||
                    _fee == _updateFee,
                "Update fee: wrong update fee value"
            );
            _;
            return;
        }

        // check mint fee
        require(
            (_fee == walletMintFee && _fee > 0) ||
                whitelist[_wallet][calcModel] ||
                _fee == _mintFee ||
                calculationModelToMintCountUsed[calcModel] <
                calculationModelToFreeMintCount[calcModel],
            "Mint fee: wrong mint fee value"
        );
        _;
    }

    /**
     * @dev Emitted when a score is minted or changed.
     * @param tokenId The changed token id.
     * @param owner The address to which the score is being changed.
     * @param score The score being changed.
     * @param calculationModel The scoring calculation model.
     * @param chainId The blockchain id in which the score was calculated.
     */
    event ChangedScore(
        uint256 indexed tokenId,
        address indexed owner,
        uint16 score,
        uint16 calculationModel,
        uint256 chainId,
        string metadataUrl,
        string referralCode,
        string referrerCode
    );

    /**
     * @dev Emitted when the owner of the contract withdraws the funds from the contract balance.
     * @param owner The address of the owner who withdrew the funds.
     * @param balance The amount of funds withdrawn by the owner.
     */
    event Withdrawal(address indexed owner, uint256 indexed balance);

    /**
     * @dev Emitted when the referrer withdraws the own referral rewards from the contract balance.
     * @param owner The address of the referrer who withdrew the referral rewards.
     * @param balance The amount of referral rewards withdrawn by the referrer.
     * @param timestamp The timestamp when the referral rewards were withdrawn.
     * @param referralCount The number of claimable referrals for the referrer.
     */
    event ClaimedReferralReward(
        address indexed owner,
        uint256 indexed balance,
        uint referralCount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when the referred wallet added the own referral rewards from the contract balance.
     */
    event RewardedWallet(address indexed wallet, uint256 timestamp);

    /**
     * @dev Emitted when the wallet is added to whitelist or removed from it for calculation model.
     * @param wallet The address of the wallet.
     * @param calculationModel The scoring calculation model.
     * @param status The status of the wallet in whitelist.
     */
    event ChangedWhitelistStatus(
        address indexed wallet,
        uint16 indexed calculationModel,
        bool indexed status
    );

    /**
     * @dev Emitted when the mint fee is changed.
     * @param mintFee The new mint fee.
     */
    event ChangedMintFee(uint256 indexed mintFee);

    /**
     * @dev Emitted when the update fee is changed.
     * @param updateFee The new update fee.
     */
    event ChangedUpdateFee(uint256 indexed updateFee);

    /**
     * @dev Emitted when the referral reward is changed.
     * @param referralReward The new referral reward.
     */
    event ChangedReferralReward(uint256 indexed referralReward);

    /**
     * @dev Emitted when the individual mint fee is changed.
     * @param wallet The address of the wallet.
     * @param calculationModel The scoring calculation model.
     * @param mintFee The new individual mint fee.
     */
    event ChangedIndividualMintFee(
        address indexed wallet,
        uint16 indexed calculationModel,
        uint256 indexed mintFee
    );

    /**
     * @dev Emitted when the individual update fee is changed.
     * @param wallet The address of the wallet.
     * @param calculationModel The scoring calculation model.
     * @param updateFee The new individual update fee.
     */
    event ChangedIndividualUpdateFee(
        address indexed wallet,
        uint16 indexed calculationModel,
        uint256 indexed updateFee
    );

    /**
     * @dev Emitted when the free mint count is changed for calculation model.
     */
    event ChangedFreeMintCount(
        uint16 indexed calculationModel,
        uint16 indexed freeMintCount
    );

    /**
     * @dev Emitted when the base URI is changed.
     * @param baseUri The new base URI.
     */
    event ChangedBaseURI(string indexed baseUri);

    /**
     * Emitted when the calculation models count is changed.
     */
    event ChangedCalculationModelsCount(uint256 indexed calcModelsCount);

    /*#########################
    ##      Constructor      ##
    ##########################*/

    /**
     * @dev Constructor for the NomisScore ERC721Upgradeable contract.
     * @param initialFee The initial minting fee for the contract.
     * @param initialCalcModelsCount The initial scoring calculation models count.
     * Initializes the token ID counter to zero and sets the initial minting fee.
     */
    function initialize(
        uint256 initialFee,
        uint16 initialCalcModelsCount
    ) public initializer {
        __ERC721_init("NomisScore", "NMSS");
        __EIP712_init("NMSS", "0.8");
        __Ownable_init();

        _tokenIds.increment();
        _mintFee = initialFee;
        _updateFee = initialFee;
        require(
            initialCalcModelsCount > 0,
            "constructor: initialCalcModelsCount should be greater than 0"
        );
        _calcModelsCount = initialCalcModelsCount;
    }

    /*#########################
    ##    Write Functions    ##
    ##########################*/

    /**
     * @dev Sets the NomisONFT address.
     * @param _nomisONFT NomisONFT address.
     */
    function setNomisONFT(address _nomisONFT) external onlyOwner {
        nomisONFT = _nomisONFT;
    }

    /**
     * @dev Sets the score for the calling address.
     * @param signature The signature used to verify the message.
     * @param score The score being set.
     * @param calculationModel The scoring calculation model.
     * @param deadline The deadline for submitting the transaction.
     * @param metadataUrl The URI for the token metadata.
     * @param chainId The blockchain id in which the score was calculated.
     * @param referralCode The minter referral code.
     * @param referrerCode The referrer code.
     * @param onftMetadataURI The URI for the ONFT token metadata.
     */
    function setScore(
        bytes calldata signature,
        uint16 score,
        uint16 calculationModel,
        uint256 deadline,
        string calldata metadataUrl,
        uint256 chainId,
        string calldata referralCode,
        string calldata referrerCode,
        string calldata onftMetadataURI
    ) external payable whenNotPaused equalsFee(calculationModel, chainId) {
        require(score <= 10000, "setScore: Score must be less than 10000");
        require(
            block.timestamp <= deadline,
            "setScore: Signed transaction expired"
        );
        require(
            calculationModel < _calcModelsCount,
            "setScore: calculationModel should be less than calculation model count"
        );

        bytes32 referralCodeBytes = keccak256(bytes(referralCode));
        bytes32 referrerCodeBytes = keccak256(bytes(referrerCode));

        // Verify the signer of the message
        bytes32 messageHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "SetScoreMessage(uint16 score,uint16 calculationModel,address to,uint256 nonce,uint256 deadline,bytes32 metadataUrl,uint256 chainId,bytes32 referralCode,bytes32 referrerCode)"
                    ),
                    score,
                    calculationModel,
                    msg.sender,
                    _nonce[msg.sender]++,
                    deadline,
                    keccak256(bytes(metadataUrl)),
                    chainId,
                    referralCodeBytes,
                    referrerCodeBytes
                )
            )
        );

        address signer = ECDSAUpgradeable.recover(messageHash, signature);
        require(
            signer == owner() && signer != address(0),
            "setScore: Invalid signature"
        );

        bool isNewScore = false;
        Score storage scoreStruct = _score[msg.sender][chainId][
            calculationModel
        ];
        if (scoreStruct.updated == 0) {
            isNewScore = true;
            scoreStruct.tokenId = _tokenIds.current();
        }

        uint256 tokenId = scoreStruct.tokenId;
        scoreStruct.updated = block.timestamp;
        if (scoreStruct.value != score) {
            scoreStruct.value = score;
        }

        if (isNewScore) {
            _walletToReferralCode[msg.sender] = referralCode;
            _referralCodeToWallet[referralCodeBytes] = msg.sender;
            _referrerCodeToTokenIds[referrerCodeBytes].push(tokenId);

            _safeMint(msg.sender, tokenId);
            _tokenIds.increment();
            ++calculationModelToMintCountUsed[calculationModel];

            tokenIdToCalcModel[tokenId] = calculationModel;
            tokenIdToChainId[tokenId] = chainId;
            _walletToTokenIds[msg.sender].push(tokenId);

            if (nomisONFT != address(0)) {
                INomisONFT(nomisONFT).mint(msg.sender, tokenId, onftMetadataURI);
            }
        }

        _setTokenURI(tokenId, metadataUrl);

        emit ChangedScore(
            tokenId,
            msg.sender,
            score,
            calculationModel,
            chainId,
            metadataUrl,
            referralCode,
            referrerCode
        );
    }

    /**
     * @dev Claim referral rewards.
     */
    function claimReferralRewards() external whenNotPaused {
        uint256 claimableReward = 0;

        // get reward value per referral
        uint256 rewardValue = 0;
        if (_individualReward[msg.sender] > 0) {
            rewardValue = _individualReward[msg.sender];
        } else {
            rewardValue = _referralReward;
        }

        // get all referrals for sender
        address[] memory referrals = getWalletsByReferrerCode(
            _walletToReferralCode[msg.sender]
        );

        // get claimableReward for all not claimed referrals
        uint256 referralsCount = 0;
        for (uint256 i = 0; i < referrals.length; ++i) {
            if (referrals[i] == msg.sender) {
                continue;
            }

            if (!_alreadyRewardedWallet[referrals[i]]) {
                // check if referral tokenIds value lt then mint free count
                bool needPay;
                uint256[] memory tokenIds = _walletToTokenIds[referrals[i]];
                for (uint256 j = 0; j < tokenIds.length; ++j) {
                    uint16 freeMintCount = calculationModelToFreeMintCount[
                        tokenIdToCalcModel[tokenIds[j]]
                    ];
                    if (freeMintCount == 0) {
                        needPay = true;
                        break;
                    }

                    if (freeMintCount < tokenIds[j]) {
                        needPay = true;
                    }
                }

                if (needPay) {
                    ++referralsCount;
                    _alreadyRewardedWallet[referrals[i]] = true;

                    emit RewardedWallet(referrals[i], block.timestamp);
                }
            }
        }

        claimableReward = referralsCount * rewardValue;

        require(
            claimableReward > 0,
            "claimReferralRewards: No rewards available"
        );
        require(
            claimableReward <= address(this).balance,
            "claimReferralRewards: Insufficient funds"
        );

        (bool success, ) = msg.sender.call{value: claimableReward}("");
        require(success, "claimReferralRewards: transfer failed");

        emit ClaimedReferralReward(
            msg.sender,
            claimableReward,
            referralsCount,
            block.timestamp
        );
    }

    /**
     * @dev Adds the given addresses to the whitelist.
     * @param actors The addresses to be added to the whitelist.
     * @param calcModel The scoring calculation model.
     */
    function whitelistAddresses(
        address[] calldata actors,
        uint16 calcModel
    ) external onlyOwner {
        for (uint256 i = 0; i < actors.length; ++i) {
            whitelist[actors[i]][calcModel] = true;

            emit ChangedWhitelistStatus(actors[i], calcModel, true);
        }
    }

    /**
     * @dev Removes the given addresses from the whitelist.
     * @param actors The addresses to be removed from the whitelist.
     * @param calcModel The scoring calculation model.
     */
    function unWhitelistAddresses(
        address[] calldata actors,
        uint16 calcModel
    ) external onlyOwner {
        for (uint256 i = 0; i < actors.length; ++i) {
            whitelist[actors[i]][calcModel] = false;

            emit ChangedWhitelistStatus(actors[i], calcModel, false);
        }
    }

    /**
     * @dev Sets the new mint fee.
     * @param mintFee The new mint fee.
     * @notice Only the contract owner can call this function.
     */
    function setMintFee(uint256 mintFee) external onlyOwner {
        _mintFee = mintFee;

        emit ChangedMintFee(mintFee);
    }

    /**
     * @dev Sets the new update fee.
     * @param updateFee The new update fee.
     * @notice Only the contract owner can call this function.
     */
    function setUpdateFee(uint256 updateFee) external onlyOwner {
        _updateFee = updateFee;

        emit ChangedUpdateFee(updateFee);
    }

    /**
     * @dev Sets the referral reward.
     * @param referralReward The referral reward.
     * @notice Only the contract owner can call this function.
     * @notice The referral reward is the amount of native currency that will be paid to the referrer when a new score is minted.
     */
    function setReferralReward(uint256 referralReward) external onlyOwner {
        _referralReward = referralReward;

        emit ChangedReferralReward(referralReward);
    }

    /**
     * @dev Sets the individual mint fee for the given address.
     * @param wallet The address to set the individual mint fee for.
     * @param calcModel The scoring calculation model.
     * @param fee The individual mint fee.
     * @notice Only the contract owner can call this function.
     */
    function setIndividualMintFee(
        address wallet,
        uint16 calcModel,
        uint256 fee
    ) external onlyOwner {
        _individualMintFee[wallet][calcModel] = fee;

        emit ChangedIndividualMintFee(wallet, calcModel, fee);
    }

    /**
     * @dev Sets the individual update fee for the given address.
     * @param wallet The address to set the individual update fee for.
     * @param calcModel The scoring calculation model.
     * @param fee The individual update fee.
     * @notice Only the contract owner can call this function.
     */
    function setIndividualUpdateFee(
        address wallet,
        uint16 calcModel,
        uint256 fee
    ) external onlyOwner {
        _individualUpdateFee[wallet][calcModel] = fee;

        emit ChangedIndividualUpdateFee(wallet, calcModel, fee);
    }

    /**
     * @dev Sets the new free mint count for given scoring calculation model.
     * @param freeMintCount The new free mint count.
     * @param calcModel The scoring calculation model.
     * @notice Only the contract owner can call this function.
     */
    function setFreeMints(
        uint16 freeMintCount,
        uint16 calcModel
    ) external onlyOwner {
        calculationModelToFreeMintCount[calcModel] = freeMintCount;

        emit ChangedFreeMintCount(calcModel, freeMintCount);
    }

    /**
     * @dev Allows the contract owner to withdraw a specific amount of native balance held by the contract.
     * Can only be called by the owner.
     * Emits a {Withdrawal} event upon successful withdrawal.
     * Throws a require error if there are no funds available for withdrawal.
     * Throws a require error if the specified withdrawal amount is greater than the contract balance.
     * @param amount The amount of balance to be withdrawn.
     */
    function withdraw(uint256 amount) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Withdrawal: No funds available");
        require(amount <= balance, "Withdrawal: Insufficient funds");

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal: transfer failed");

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @dev Pauses the contract.
     * See {Pausable-_pause}.
     * Can only be called by the owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     * See {Pausable-_unpause}.
     * Can only be called by the owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Changes the base URI for token metadata.
     * @param baseUri The new base URI.
     */
    function setBaseUri(string memory baseUri) external onlyOwner {
        _baseUri = baseUri;

        emit ChangedBaseURI(baseUri);
    }

    /**
     * @dev Sets the number of scoring calculation models.
     * @param calcModelsCount The number of scoring calculation models to set.
     */
    function setCalcModelsCount(uint16 calcModelsCount) external onlyOwner {
        require(
            calcModelsCount > 0,
            "setCalcModelsCount: calcModelsCount should be greater than 0"
        );
        _calcModelsCount = calcModelsCount;

        emit ChangedCalculationModelsCount(calcModelsCount);
    }

    /*#########################
    ##    Read Functions    ##
    ##########################*/

    /**
     * @dev Get the current token id.
     * @return The current token id.
     */
    function getCurrentTokenId() external view returns (uint256) {
        return _tokenIds.current();
    }

    /**
     * @dev Returns the referral code for the given address.
     * @param addr The address to get the referral code for.
     * @return The referral code for the given address.
     */
    function getReferralCode(
        address addr
    ) external view returns (string memory) {
        return _walletToReferralCode[addr];
    }

    /**
     * @dev Returns the address for the given referral code.
     * @param referralCode The referral code to get the wallet for.
     * @return The address for the given referral code.
     */
    function getWalletByReferralCode(
        string memory referralCode
    ) external view returns (address) {
        return getWalletByReferralCode(keccak256(bytes(referralCode)));
    }

    /**
     * @dev Returns the address for the given referral code.
     * @param referralCode The referral code to get the wallet for.
     * @return The address for the given referral code.
     */
    function getWalletByReferralCode(
        bytes32 referralCode
    ) private view returns (address) {
        require(
            referralCode != 0,
            "getWalletByReferralCode: Invalid referral code"
        );

        return _referralCodeToWallet[referralCode];
    }

    /**
     * @dev Returns the wallets for the given referrer code.
     * @param referrerCode The referrer code to get the wallets for.
     * @return The wallets for the given referrer code.
     */
    function getWalletsByReferrerCode(
        string memory referrerCode
    ) public view returns (address[] memory) {
        uint256[] memory referredTokenIds = _referrerCodeToTokenIds[
            keccak256(bytes(referrerCode))
        ];

        // Create a new dynamic array with the correct size to store valid token IDs
        address[] memory wallets = new address[](referredTokenIds.length);

        // Copy the valid token IDs to the new array
        for (uint256 i = 0; i < referredTokenIds.length; ++i) {
            wallets[i] = ownerOf(referredTokenIds[i]);
        }

        return wallets;
    }

    /**
     * @dev Returns the claimable reward for the given wallet.
     * @param wallet The wallet to get the claimable reward for.
     * @return The claimable reward for the given wallet.
     */
    function getClaimableReward(
        address wallet
    ) external view returns (uint256) {
        uint256 claimableReward = 0;

        // get reward value per referral
        uint256 rewardValue = 0;
        if (_individualReward[wallet] > 0) {
            rewardValue = _individualReward[wallet];
        } else {
            rewardValue = _referralReward;
        }

        // get all referrals for sender
        address[] memory referrals = getWalletsByReferrerCode(
            _walletToReferralCode[wallet]
        );

        // get claimableReward for all not claimed referrals
        for (uint256 i = 0; i < referrals.length; ++i) {
            if (referrals[i] == wallet) {
                continue;
            }

            if (!_alreadyRewardedWallet[referrals[i]]) {
                // check if referral tokenIds value lt then mint free count
                bool needPay;
                uint256[] memory tokenIds = _walletToTokenIds[referrals[i]];
                for (uint256 j = 0; j < tokenIds.length; ++j) {
                    uint16 freeMintCount = calculationModelToFreeMintCount[
                        tokenIdToCalcModel[tokenIds[j]]
                    ];
                    if (freeMintCount == 0) {
                        needPay = true;
                        continue;
                    }

                    if (freeMintCount < tokenIds[j]) {
                        needPay = true;
                    }
                }

                if (needPay) {
                    claimableReward += rewardValue;
                }
            }
        }

        return claimableReward;
    }

    /**
     * @dev Returns the score and associated metadata for a given address.
     * @param addr The address to get the score for.
     * @param blockchainId The blockchain id in which the score was calculated.
     * @param calcModel The scoring calculation model.
     * @return score The score for the specified address.
     * @return updated The timestamp when the score was last updated for the specified address.
     * @return tokenId The token id with score for the specified address.
     * @return calculationModel The scoring calculation model.
     * @return chainId The blockchain id in which the score was calculated.
     * @return owner The score owner.
     */
    function getScore(
        address addr,
        uint256 blockchainId,
        uint16 calcModel
    )
        external
        view
        returns (
            uint16 score,
            uint256 updated,
            uint256 tokenId,
            uint16 calculationModel,
            uint256 chainId,
            address owner
        )
    {
        Score storage scoreStruct = _score[addr][blockchainId][calcModel];

        score = scoreStruct.value;
        updated = scoreStruct.updated;
        tokenId = scoreStruct.tokenId;
        calculationModel = calcModel;
        chainId = blockchainId;
        owner = addr;
    }

    /**
     * @dev Returns the score and associated metadata for a given token id.
     * @param id The token id to get the score for.
     * @return score The score for the specified address.
     * @return updated The timestamp when the score was last updated for the specified address.
     * @return tokenId The token id with score for the specified address.
     * @return calculationModel The scoring calculation model.
     * @return chainId The blockchain id in which the score was calculated.
     * @return owner The score owner.
     */
    function getScoreByTokenId(
        uint256 id
    )
        external
        view
        returns (
            uint16 score,
            uint256 updated,
            uint256 tokenId,
            uint16 calculationModel,
            uint256 chainId,
            address owner
        )
    {
        address scoreOwner = ownerOf(id);
        calculationModel = tokenIdToCalcModel[id];
        chainId = tokenIdToChainId[id];

        Score storage scoreStruct = _score[scoreOwner][chainId][
            calculationModel
        ];

        score = scoreStruct.value;
        updated = scoreStruct.updated;
        tokenId = scoreStruct.tokenId;
        owner = scoreOwner;
    }

    /**
     * @dev Returns the token IDs associated with a given address.
     * @param addr The address for which to retrieve the token IDs.
     * @return An array of token IDs owned by the specified address.
     */
    function getTokenIds(
        address addr
    ) external view returns (uint256[] memory) {
        require(_tokenIds.current() > 0, "getTokenIds: No tokens minted");

        return _walletToTokenIds[addr];
    }

    /**
     * @dev Returns the current mint fee.
     * @return The current mint fee.
     */
    function getMintFee() external view returns (uint256) {
        return _mintFee;
    }

    /**
     * @dev Returns the current update fee.
     * @return The current update fee.
     */
    function getUpdateFee() external view returns (uint256) {
        return _updateFee;
    }

    /**
     * @dev Returns the current referral reward.
     * @return The current referral reward.
     * @notice Only the contract owner can call this function.
     */
    function getReferralReward() external view returns (uint256) {
        return _referralReward;
    }

    /**
     * @dev Sets the individual mint fee for the given address.
     * @param wallet The address to set the individual mint fee for.
     * @param calcModel The scoring calculation model.
     * @return The individual mint fee.
     * @notice Only the contract owner can call this function.
     */
    function getIndividualMintFee(
        address wallet,
        uint16 calcModel
    ) external view returns (uint256) {
        return _individualMintFee[wallet][calcModel];
    }

    /**
     * @dev Sets the individual update fee for the given address.
     * @param wallet The address to set the individual update fee for.
     * @param calcModel The scoring calculation model.
     * @return The individual update fee.
     * @notice Only the contract owner can call this function.
     */
    function getIndividualUpdateFee(
        address wallet,
        uint16 calcModel
    ) external view returns (uint256) {
        return _individualUpdateFee[wallet][calcModel];
    }

    /**
     * @dev Returns the current free mint count for given scoring calculation model.
     * @param calcModel The scoring calculation model.
     * @return The current free mint count.
     */
    function getFreeMints(uint16 calcModel) external view returns (uint16) {
        return calculationModelToFreeMintCount[calcModel];
    }

    /**
     * @dev Returns the base URI of the token. This method is called internally by the {tokenURI} method.
     * @return A string containing the base URI of the token.
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    /**
     * @dev Returns an URI for a given token ID.
     * This method is called by the {tokenURI} method from ERC721Upgradeable contract, which in turn can be called by clients to get metadata.
     * @param tokenId The token ID to query for the URI.
     * @return A string containing the URI for the given token ID.
     */
    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Returns the number of scoring calculation models.
     * @return The number of scoring calculation models.
     */
    function getCalcModelsCount() external view returns (uint16) {
        return _calcModelsCount;
    }

    /**
     * @dev Returns the nonce value for the calling address.
     * @param addr The address to get the nonce for.
     * @return The nonce value for the calling address.
     */
    function getNonce(address addr) external view returns (uint256) {
        return _nonce[addr];
    }

    /**
     * @dev Hook that is called before any token transfer.
     * @param from The address to transfer from.
     * @param to The address to transfer to.
     * @param tokenId The ID of the token being transferred.
     * @param batchSize The batch size.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable) {
        require(
            from == address(0),
            "NonTransferrableERC721Token: Nomis score can't be transferred."
        );
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
