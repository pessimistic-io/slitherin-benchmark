// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^``,|>!*%%%%*/<|,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// ^^^^^^^^^^^^^^^^^^^^^^^`,|<>!*%%%%%*/>>/*%%%%%*!>|.,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// ^^^^^^^^^^^^^^^^`,.|>/*%%%%%*!><.,`^^^^^^`,.</!*%%%%%*/<|,``^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// ^^^^^^^^^`,,|>/!*%%%%*!><|,``^^^^^^^^^^^^^^^^^^`,,|>/*%%%%%*!><|,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// ^^^`,.</!*%%%%%%%%%%!>|,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.|>/*%%%%%*/>|`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// >/!%%%%%*!>|.,`.|</!*%%%%%!/<.,`^^^^^^^^^^^^^^^^^^^^^^^``,|</%%%%%%%%%.^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%%|,`^^^^^^^^^^^^`,.|>!*%%%%%*!>|.,`^^^^^^^^^``,|</!*%%%%%!/<>%%%%%.^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^^^^^^^^^^^^^^^^^`,.<>!*%%%%%*/<|..<>!*%%%%%*/>|.,`^^^`%%%%%.^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^^`,,,`^^^^^^^^^^^^^^^^^`,|</!%%%%%%%*!><.,`^^^^^^^^^^,%%%%%.^^^^^^^^^^^^^^^^^^^^^^^`,,,,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^.%%%%*!/<|.`^^^^^^^^^^^^^^^^^,%%%%%|`^^^^^^^^^^^^^^^^,%%%%%.^^^^^^^^^^^^^^^^``,|</!*%%%%*!><|,``^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^.%%%%%%%%%%!`^^^^^^^^^^^^^^^^`%%%%%|^^^^^^^^^^^^^^^^^,%%%%%.^^^^^^^^^^`,.<>!*%%%%%*/><|>/*%%%%%*!><.,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^.%%%%/<%%%%*`^^^^^^^^^^^^^^^^`%%%%%|^^^^^^^^^^^^^^^^^,%%%%%.^^^``,|</*%%%%%*!><.,`^^^^^^^^`,|<>!*%%%%%*/>|.,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^.%%%%%%%%%%*`^^^^^^^^^^^^^^^^`%%%%%|^^^^^^^^^^^^^^^^^`%%%%%></!*%%%%%!><|,``^^^^^^^^^^^^^^^^^^^^``,|</!*%%%%%!/<.,``^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^,/!*%%%%%%%%`^^^^^^^^^^^^^^^^`%%%%%|^^^^^^^^^^^^^^`,.>%%%%%%%%*%%%%%*/>|,,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^``.|</*%%%%%*/>,^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^^^^`,.|>//>.^^^^^^^^^^^^^^^^^`%%%%%|^^^^^^^^^^^`/!%%%%%*!><.,```,|</!*%%%%*!/<|,,`^^^^^^^^^^^^^^^^^^^^``,|</!%%%%%%%%%.^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`%%%%%|^^^^^^^^^^^`%%%%%<``^^^^^^^^^^^^^`,.|</*%%%%%*!/<.,`^^^^^^^^`,|</!*%%%%%!/>||%%%%%.^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`%%%%%|^^^^^``,|</!%%%%%|^^^^^^^^^^^^^^^^^^^^^^`,.<>!*%%%%%*!>||>/*%%%%%*/>|.,`^^^^`%%%%%.^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^`,.|.,`^^^^^^^^^^^^^^^^^^^^^^`%%%%%<,.<>!*%%%%%%%%%%%|^^^^^`,.|.,`^^^^^^^^^^^^^^^^^`,.</!%%%%%%!><.,``^^^^^^^^^^,%%%%%.^^^^^^^^^^^^^^^^^^^^^^^`,.|.,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^.%%%%%*!/<|,^^^^^^^^^^^^^^^^^`%%%%%%%%%%*!><|,``%%%%%|^^^^^.%%%%%%!/>|.^^^^^^^^^^^^^^^^^^>%%%%<^^^^^^^^^^^^^^^^^,%%%%%.^^^^^^^^^^^^^^^^`,.<>!*%%%%%%%*/<|.``^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^.%%%%**%%%%*`^^^^^^^^^^^^^^^^`/*%%%%%%%/<.`^^^`.%%%%%|^^^^^.%%%%%*%%%%%`^^^^^^^^^^^^^^^^^<%%%%|^^^^^^^^^^^^^^^^^,%%%%%.^^^^^^^^^`,.|>/*%%%%%*!><..|>/*%%%%%*!><.,``^^^^^^^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^.%%%%/<%%%%*`^^^^^^^^^^^^^^^^^^^`,.<>!*%%%%*!*%%%%%%%|^^^^^.%%%%%>%%%%%`^^^^^^^^^^^^^^^^^>%%%%|^^^^^^^^^^^^^^^^^,%%%%%.^^``.|</!*%%%%%!/<.,`^^^^^^^^^^`,.|>/*%%%%%*/><.,`^^^^^^^^^^^^^^^^^^^^
// %%%%*^^^^^^.%%%%%%%%%%*`^^^^^^^^^^^^^^^^^^^^^^^^^``,|%%%%%>%%%%%|^^^^^.%%%%%%%%%%*`^^^^^^^^^^^^^^^^^>%%%%|^^^^^^^^^^^^^^^^^`%%%%%/>!*%%%%%*/<|,``^^^^^^^^^^^^^^^^^^^^^^^`,|</!*%%%%%!/>|.,`^^^^^^^^^^^^^
// %%%%*^^^^^^`<>!*%%%%%%*`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*%%%%`*%%%%|^^^^^`<>/*%%%%%%%`^^^^^^^^^^^^^^^^^>%%%%|^^^^^^^^^^^^^`,.|/%%%%%%%*!*%%%%%*/>|.,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,|>*%%%%%%*!,^^^^^^^^^^^
// %%%%%/<|.``^^^^^`.|<<|,^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*%%%%,*%%%%|^^^^^^^^^``,.<<<.^^^^^^^^^^^^^^^^^^>%%%%|^^^^^^^^^^^`!*%%%%*!><|,``^^`,.</!*%%%%%*/>|.``^^^^^^^^^^^^^^^^^^^`,.</!*%%%%%%%%%.^^^^^^^^^^^
// ,|</!%%%%%*!/<|,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*%%%%,*%%%%|^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^>%%%%|^^^^^^^^^^^`%%%%%<`^^^^^^^^^^^^^^^`,,|>/!%%%%%*!/<|.``^^^^^`,.|>!*%%%%%*/>|.,/%%%%.^^^^^^^^^^^
// ^^^^^`,.<>/*%%%%%*!><.,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*%%%%,*%%%%|^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^>%%%%|^^^^^`,.</!*%%%%%|^^^^^^^^^^^^^^^^^^^^^^^`,.|>/*%%%%%*/>>/!%%%%%*!>|.,`^^^^^^>%%%%.^^^^^^^^^^^
// ^^^^^^^^^^^^`,.<>!*%%%%%!/>|.,`^^^^^^^^^^^^^^^^^^^^^^*%%%%,*%%%%|^^^^^`|<<<.,`^^^^^^^^^^^^^^^^^^^^^^>%%%%>.|<!*%%%%%*!%%%%%|^^^^^`.<<<|,``^^^^^^^^^^^^^^^^`,.<>*%%%%%/<.,``^^^^^^^^^^^^>%%%%.^^^^^^^^^^^
// ^^^^^^^^^^^^^^^^^^``.|</!*%%%%%!/<|,`^^^^^^^^^^^^^^^^*%%%%,*%%%%|^^^^^.%%%%%%%!/>|^^^^^^^^^^^^^^^^^^>%%%%%%%%*!><|,`^^*%%%%|^^^^^.%%%%%%%*/>|`^^^^^^^^^^^^^^^^^<%%%%*^^^^^^^^^^^^^^^^^^>%%%%.^^^^^^^^^^^
// ^^^^^^^^^^^^^^^^^^^^^^^^^`,.|>/*%%%%%*!><.,`^^^^^^^^^*%%%%,*%%%%|^^^^^.%%%%%!%%%%%`^^^^^^^^^^^^^^^^^./*%%%%%%!>|.```,|%%%%%|^^^^^.%%%%%!%%%%%`^^^^^^^^^^^^^^^^^<%%%%*^^^^^^^^^^^^^^^^^^>%%%%.^^^^^^^^^^^
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.|>!*%%%%%*/<|.,`^^*%%%%,*%%%%|^^^^^.%%%%%/%%%%*`^^^^^^^^^^^^^^^^^^^^`,.<>/*%%%%%%%%%%%%%|^^^^^.%%%%%/%%%%%`^^^^^^^^^^^^^^^^^<%%%%*^^^^^^^^^^^^^^^^^^>%%%%.^^^^^^^^^^^
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,|</!*%%%%*!/%%%%%!%%%%%|^^^^^.%%%%%%%%%%%`^^^^^^^^^^^^^^^^^^^^^^^^^^``,*%%%%!*%%%%|^^^^^.%%%%%%%%%%%`^^^^^^^^^^^^^^^^^<%%%%*^^^^^^^^^^^^^^^^^^>%%%%.^^^^^^^^^^^
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.|>/*%%%%%%%%%%%%|^^^^^`.<>!*%%%%%*`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^!%%%%>*%%%%|^^^^^`.<>/*%%%%%*`^^^^^^^^^^^^^^^^^<%%%%*^^^^^^^^^^^^^^^^^^>%%%%.^^^^^^^^^^^
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.|.,,*%%%%*/>|.,`^^^^^`,.|.,^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^!%%%%>*%%%%|^^^^^^^^^^^`,.|.,^^^^^^^^^^^^^^^^^^<%%%%*^^^^^^^^^^^^^^^^^`/%%%%|^^^^^^^^^^^
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,|<>!*%%%%%!/<|,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^!%%%%>*%%%%|^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^<%%%%*^^^^^^^^^^^`,.</!*%%%%%%*!>|.,`^^^^
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^``.|</*%%%%%*!><.,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^!%%%%>*%%%%|^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^<%%%%*^^^^`,.<>!*%%%%%*!>|..<>!*%%%%*!/<|
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.|>!*%%%%%*/>|.,`^^^^^^^^^^^^^^^^^^^^^!%%%%>*%%%%|^^^^^`|>/><.,`^^^^^^^^^^^^^^^^^^^^^<%%%%*|</!%%%%%*!/<.,`^^^^^``.|>*%%%%%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.</!*%%%%*!/<|.,`^^^^^^^^^^^^^^!%%%%>*%%%%|^^^^^.%%%%%%%%*/>`^^^^^^^^^^^^^^^^^<%%%%%%%%*/<|,`^^^^^``,|>/!%%%%%*!><*%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.|</!%%%%%*!/<.,`^^^^^^^^!%%%%>*%%%%|^^^^^.%%%%%/%%%%%`^^^^^^^^^^^^^^^^^,</!*%%%%*!><.,,.</!*%%%%%!/<|.``^^^*%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.<>/*%%%%%*!>|.,`^!%%%%>*%%%%|^^^^^.%%%%%/%%%%%`^^^^^^^^^^^^^^^^^^^^^`,.|>!*%%%%%%%%*!>|.,`^^^^^^^^^^*%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,|<>!*%%%%%*%%%%%%%%%%%|^^^^^,%%%%%%%%%%%`^^^^^^^^^^^^^^^^^^^^^^^^^^^^`*%%%%/`^^^^^^^^^^^^^^^^^*%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^``,|</!*%%%%*%%%%%<`^^^^^,.|>/!*%%%*`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^!%%%%>^^^^^^^^^^^^^^^^^^*%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,,,``!%%%%%*/><.,`^^^^^`,,,`^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^!%%%%>^^^^^^^^^^^^^^^^^^*%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.<>!*%%%%%*/>|.,^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^!%%%%>^^^^^^^^^^^^^^^^^^*%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^``.|</!*%%%%*!/<.,`^^^^^^^^^^^^^^^^^^^^^^^^^^^!%%%%>^^^^^^^^^^^^^^^^^^*%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.|>/*%%%%%*!>|.,`^^^^^^^^^^^^^^^^^^^^!%%%%>^^^^^^^^^^^^^^^^^^*%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.<>!*%%%%%*/>|.``^^^^^^^^^^^^^!%%%%>^^^^^^^^^^^^^`,.|>%%%%%
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,|</!%%%%%%!/<|.``^^^^^^!%%%%>^^^^^^``,|</!%%%%%*!><.
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.|>/*%%%%%*!><.,`!%%%%>`,.<>!*%%%%%*/<|.``^^^^
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^`,.<>/*%%%%%%%%%%%%%%%%*!>|.,`^^^^^^^^^^^
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^``,|</*%%%%*/<|.`^^^^^^^^^^^^^^^^^^

import {ERC721} from "./ERC721.sol";
import {VRFCoordinatorV2Interface} from "./VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "./VRFConsumerBaseV2.sol";
import {AccessControl} from "./AccessControl.sol";
import {Pausable} from "./Pausable.sol";
import {Counters} from "./Counters.sol";

/**
 * @title Billy Bouts Bettn Token.
 * @author Bill Bout.
 * @notice This is a Collectable to commemorate the billionaire bout.
 * @notice This token can be used to unlock bills bettn system.
 */
contract BillyBoutsBettnToken is
    ERC721,
    AccessControl,
    VRFConsumerBaseV2,
    Pausable
{
    error BBBToken__MaxSupplyAlreadyMet();
    error BBBToken__FighterOutOfRange();
    error BBBToken__MintPriceNotPaid();
    error BBBToken__WithdrawTransferFailed();
    error BBBToken__BurnerIsNotOwner();

    using Counters for Counters.Counter;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    string private constant TOKEN_NAME = "BillyBoutsBettnToken";
    string private constant TOKEN_SYMBOL = "BBB";
    uint256 private constant MAX_SUPPLY = 888_888; // BBB_BBB
    uint256 private constant TOKEN_PRICE = 0.016 ether;
    uint32 private constant NUM_WORDS = 3;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint16 private constant BIG_RNG_MOD = 1_000;
    uint8 private constant RNG_MOD = 100;

    /// @notice Variables for VRF
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;

    /// @notice Holds reference to last used tokenId
    Counters.Counter private s_tokenIdCount;

    /// @notice Mapping of request ids to sender addresses.
    /// @dev Required for reference across VRF functions.
    mapping(uint256 => address) private s_requestIdToSender;
    mapping(uint256 => uint256) private s_requestIdToTokenId;

    /// @notice Holds both scores in private variables.
    uint256 private s_ZuckScore;
    uint256 private s_MuskScore;

    /// @notice Holds base URI.
    /// @dev Append tokenId to get token metadata.
    string private baseTokenURI;

    enum BackgroundType {
        WHITE,
        YELLOW,
        PURPLE,
        BLUE,
        GREEN
    }
    enum CoinType {
        MONO,
        PLATINUM,
        GOLD
    }
    enum Fighter {
        ZUCK,
        MUSK
    }

    /// @notice Event for when a mint is requested and VRF has accepted the job.
    /// @param requestId From VRF for mappings when fulfillRandomWords() is triggered.
    /// @param sender The sender of the request.
    event RequestMintNFT(uint256 indexed requestId, address indexed sender);

    /// @notice Event for when the mint is fulfilled.
    /// @notice This records the result of the VRF, gives full transparency of rarity result.
    /// @param tokenId The tokenId of the newly created NFT.
    /// @param requestId Set when request mint happened for mappings to sender address.
    /// @param randomWords List of random words from the VRF for token rarity.
    event MintedNFT(
        uint256 indexed tokenId,
        uint256 indexed requestId,
        uint256[] randomWords
    );

    /// @notice Constructor for child contracts ERC721 and VRF base.
    /// @notice Sets DEFAULT_ADMIN_ROLE & OWNER_ROLE to contract deploy.
    /// @param _vrfCoordinator Address for VRF, different for each chain.
    /// @param _subscriptionId Id for VRF, will use funds in this account to pay for VRF.
    /// @param _gasLane For VRF, which oracle job to use cost more = faster... I think.
    /// @param _callbackGasLimit For VRF, max gas to usein VRF, I've got some spare gas if needed.
    constructor(
        address _vrfCoordinator,
        uint64 _subscriptionId,
        bytes32 _gasLane,
        uint32 _callbackGasLimit
    ) ERC721(TOKEN_NAME, TOKEN_SYMBOL) VRFConsumerBaseV2(_vrfCoordinator) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        i_subscriptionId = _subscriptionId;
        i_gasLane = _gasLane;
        i_callbackGasLimit = _callbackGasLimit;
    }

    /// @notice Request the minting of NFT, senders VRF.
    /// @notice Minting is not done here but on VRF return.
    /// @notice The only public entry point to the contract.
    /// @dev increments tokenId here and holds reference, to stop overflow.
    /// @dev Revert if: Paused, at max supply, not paid 0.016 eth, not selected fighter.
    /// @param _fighterValue Should only be a 0 (Zuck) or 1 (Musk) anything else will revert.
    function requestMint(uint256 _fighterValue) external payable whenNotPaused {
        if (s_tokenIdCount.current() == MAX_SUPPLY) {
            revert BBBToken__MaxSupplyAlreadyMet();
        }
        if (msg.value < TOKEN_PRICE) {
            revert BBBToken__MintPriceNotPaid();
        }
        if (uint256(Fighter.MUSK) < _fighterValue) {
            revert BBBToken__FighterOutOfRange();
        }

        s_tokenIdCount.increment();
        uint256 nextId = s_tokenIdCount.current();

        Fighter _fighter = Fighter(_fighterValue);
        _incrementScore(_fighter);
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        s_requestIdToTokenId[requestId] = nextId;
        s_requestIdToSender[requestId] = msg.sender;
        emit RequestMintNFT(requestId, msg.sender);
    }

    /// @notice Trigger by VRF when work is done and random words are returned.
    /// @notice calculates all rarites on chain, to stop disputes and make system hands off.
    /// @dev The NFT is Minted here with tokenId using tokenIdCount and the user address from requestId mappings.
    /// @dev Emits MintedNFT for used to create the NFT metadata.
    /// @param _requestId Id to match against the address mappings we have saved.
    /// @param _randomWords Random words from VRF (Verifiable Random Function.)
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal virtual override {
        uint256 nextId = s_requestIdToTokenId[_requestId];
        _safeMint(s_requestIdToSender[_requestId], nextId);
        emit MintedNFT(nextId, _requestId, _randomWords);
    }

    /// @notice To withdraw funds from the contract.
    /// @dev Uses onlyRole modifier to limit to Owner role use only.
    function withdraw(address beneficiary) external onlyRole(OWNER_ROLE) {
        uint256 balance = address(this).balance;
        (bool transferTx, ) = beneficiary.call{value: balance}("");
        if (!transferTx) {
            revert BBBToken__WithdrawTransferFailed();
        }
    }

    /// @notice Set the base URI for TokenURI.
    /// @param baseURI URI to update to.
    function setBaseURI(string memory baseURI) external onlyRole(OWNER_ROLE) {
        baseTokenURI = baseURI;
    }

    function burn(
        address _tokenOwner,
        uint256 _tokenId
    ) external onlyRole(BURNER_ROLE) whenNotPaused {
        address owner = ownerOf(_tokenId);
        if (_tokenOwner != owner) {
            revert BBBToken__BurnerIsNotOwner();
        }
        _burn(_tokenId);
    }

    /// @notice as it sounds stupid.
    function pause() external onlyRole(OWNER_ROLE) {
        _pause();
    }

    /// @notice same.
    function unpause() external onlyRole(OWNER_ROLE) {
        _unpause();
    }

    /// @notice Sets an address as a burner, will be CCIP sender contract.
    function setBurnerRole(
        address _burner
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(BURNER_ROLE, _burner);
    }

    /// @notice Icrements score uses Fighter enum.
    /// @param _fighter Enum for which fighter.
    function _incrementScore(Fighter _fighter) internal {
        if (_fighter == Fighter.ZUCK) {
            s_ZuckScore++;
        } else if (_fighter == Fighter.MUSK) {
            s_MuskScore++;
        }
    }

    /// @notice Required for pausable contract.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /// @notice Gets base URI overrides ERC721.
    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    /// @notice Gets current tally as tuple.
    function getScore() external view returns (uint256, uint256) {
        return (s_ZuckScore, s_MuskScore);
    }

    /// @notice Total supply shows max supply in etherscan.
    function totalSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    /// @notice Get address by request Id.
    /// @param _requestId Id to find address against.
    function getRequestIdToSender(
        uint256 _requestId
    ) external view returns (address) {
        return s_requestIdToSender[_requestId];
    }

    /// @notice Required for Access control contract.
    /// @notice Required for Pausable contract.
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Background light rarities Array.
    /// @return Array of percentages as uint8.
    function getBackgroundChanceArray() public pure returns (uint8[5] memory) {
        //        0 - 1:        1%          chance: WHITE
        //       2 - 10:        9%          chance: YELLOW
        //      11 - 25:        15%         chance: PURPLE
        //      26 - 50:        25%         chance: BLUE
        //     51 - 100:        50%         chance: GREEN
        return [1, 10, 25, 50, 100];
    }

    /// @notice Sorts between background light rarities.
    /// @param _randomWord Random word from VRF.
    function getBackgroundRarity(
        uint256 _randomWord
    ) external pure returns (BackgroundType background) {
        uint256 randomNumber = (_randomWord % RNG_MOD) + 1;

        uint256 cumulativeSum = 0;
        uint8[5] memory chanceArray = getBackgroundChanceArray();
        for (uint256 i = 0; i < chanceArray.length; i++) {
            if (
                randomNumber > cumulativeSum && randomNumber <= chanceArray[i]
            ) {
                return BackgroundType(i);
            }
            cumulativeSum = chanceArray[i];
        }
    }

    /// @notice Coin type rarities Array.
    /// @return Array of percentages as uint16.
    function getCoinChanceArray() public pure returns (uint16[3] memory) {
        //        0 - 1:        0.1%      chance: MONO
        //      2 - 220:        21.9%     chance: PLATINUM
        //  121 - 1_000:        78%         chance: GOLD
        return [1, 220, 1000];
    }

    /// @notice Sorts between coin rarities.
    /// @param _randomWord Random word from VRF.
    function getCoinRarity(
        uint256 _randomWord
    ) external pure returns (CoinType coin) {
        uint256 randomNumber = (_randomWord % BIG_RNG_MOD) + 1;

        uint256 cumulativeSum = 0;
        uint16[3] memory chanceArray = getCoinChanceArray();
        for (uint256 i = 0; i < chanceArray.length; i++) {
            if (
                randomNumber >= cumulativeSum && randomNumber < chanceArray[i]
            ) {
                return CoinType(i);
            }
            cumulativeSum = chanceArray[i];
        }
    }

    /// @notice Is you coin a shiny
    function getIsShiny(uint256 _randomWord) external pure returns (bool) {
        //        0 - 1:        1%      chance: SHINY
        //      2 - 100:        99%     chance: NON-SHINY
        uint256 randomNumber = (_randomWord % BIG_RNG_MOD) + 1;

        if (randomNumber == 1) {
            return true;
        }
        return false;
    }
}

