// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { Strings } from "./Strings.sol";
import { Base64 } from "./Base64.sol";
import {     ERC721URIStorage,     ERC721 } from "./ERC721URIStorage.sol";
import { Counters } from "./Counters.sol";
import { Ownable } from "./Ownable.sol";
import {     ReentrancyGuard } from "./ReentrancyGuard.sol";
import { DynamicBuffer } from "./DynamicBuffer.sol";
import { QarbCodesInterface } from "./QarbCodesInterface.sol";
import { QrCode } from "./QrCode.sol";

struct QrCodeStruct {
    string text;
    string color;
}

contract QarbCodes is
    QarbCodesInterface,
    QrCode,
    ERC721URIStorage,
    Ownable,
    ReentrancyGuard
{
    using Counters for Counters.Counter;

    struct Person {
        string name;
        uint age;
    }

    Counters.Counter private _tokenIds;

    uint256 public constant MAX_COUNT_PER_TX = 5;
    uint256 public constant FREE_SUPPLY = 200;
    uint256 public constant MAX_SUPPLY = 8888;
    uint256 public constant PHASE_2_LIMIT = 1900;
    uint256 public constant PHASE_3_LIMIT = 2000;
    uint256 public constant PHASE_4_LIMIT = 2000;
    uint256 public constant PHASE_5_LIMIT = 2000;
    // PHASE_6_LIMIT is the remainder to get to max supply 8888

    uint256 public constant PHASE_1_WHITELIST_MINT_PRICE = 0 ether;
    uint256 public constant PHASE_2_MINT_PRICE = 0.00075 ether;
    uint256 public constant PHASE_3_MINT_PRICE = 0.00125 ether;
    uint256 public constant PHASE_4_MINT_PRICE = 0.00175 ether;
    uint256 public constant PHASE_5_MINT_PRICE = 0.00225 ether;
    uint256 public constant PHASE_6_MINT_PRICE = 0.00275 ether;

    uint256 private _numAvailableTokens = MAX_SUPPLY;
    uint256 private _mintedAtStartOfPublicSale;
    mapping(uint256 => QrCodeStruct) public qrCodes;
    mapping(address => uint8) private _whiteList;
    mapping(address => bool) public freeMintAddresses;

    // Minting
    // The global gate whether any of the phases has started
    bool public hasLaunched = false;
    bool public isPublicSaleActive = false;
    bool public isPhase2Active = false;
    bool public isPhase3Active = false;
    bool public isPhase4Active = false;
    bool public isPhase5Active = false;
    bool public isPhase6Active = false;
    uint public freeMintedCount = 0;

    bytes private constant _TOKEN_DESCRIPTION =
        "QaRb Codes on Arbitrum - Stored entirely on the Arbitrum Blockchain";

    event QRCodeURIGenerated(string str);

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) {}

    function setWhiteList(
        address[] calldata addresses,
        uint8 numAllowedToMint
    ) external override onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            _whiteList[addresses[i]] = numAllowedToMint;
        }
    }

    /**
     * @notice The White List Mints is active until everything is sold out, so
     *         even when the Public Sale is activated users can still claim
     *         their whitelist spot as long as the collection is not Sold Out
     *         yet.
     *
     * @param qrCodeText The text the user wants in their QaRb Code, limited
     *                   to a maximum of 42 characters.
     */
    function mintWhiteList(string memory qrCodeText) external override {
        uint8 count = 1;
        uint256 qrCodeTextLength = bytes(qrCodeText).length;

        require(
            qrCodeTextLength > 0 && qrCodeTextLength <= 42,
            "INPUT_TEXT_INVALID"
        );
        require(hasLaunched, "PUBLIC_MINT_INACTIVE");
        require(count <= _whiteList[msg.sender], "ALLOW_LIST_MAX_EXCEEDED");
        require(totalSupply() + count <= MAX_SUPPLY, "MAX_SUPPLY_EXCEEDED");
        require(count > 0, "MINT_COUNT_REQUIRED");

        _whiteList[msg.sender] -= count;

        _mint(qrCodeText, count);
    }

    /**
     * @notice The Free Mint is active once the Public Sale is activated.
     *         Every user gets 1x free mint, until 200 free mints have been
     *         minted.
     *
     * @param qrCodeText The text the user wants in their QaRb Code, limited
     *                   to a maximum of 42 characters.
     */
    function mintFree(string memory qrCodeText) external override {
        uint256 count = 1;
        uint256 qrCodeTextLength = bytes(qrCodeText).length;

        require(
            qrCodeTextLength > 0 && qrCodeTextLength <= 42,
            "INPUT_TEXT_INVALID"
        );
        require(hasLaunched && isPublicSaleActive, "PUBLIC_MINT_INACTIVE");
        require(
            freeMintAddresses[msg.sender] == false,
            "FREE_MINT_ALREADY_CLAIMED"
        );
        require(freeMintedCount < FREE_SUPPLY, "FREE_SOLD_OUT");
        require(totalSupply() + count <= MAX_SUPPLY, "MAX_SUPPLY_EXCEEDED");
        require(count > 0, "MINT_COUNT_REQUIRED");

        freeMintedCount = freeMintedCount + 1;
        freeMintAddresses[msg.sender] = true;

        _mint(qrCodeText, count);
    }

    /**
     * @notice The Paid Mint is active once the Public Sale is activated.
     *
     * @param qrCodeText The text the user wants in their QaRb Code, limited
     *                   to a maximum of 42 characters.
     * @param count      The number of QaRb Codes to mint. Limited to a certain
     *                   maximum per transaction.
     */
    function mint(
        string memory qrCodeText,
        uint256 count
    ) external payable override {
        uint256 cost = currentMintPrice();
        uint256 qrCodeTextLength = bytes(qrCodeText).length;

        require(
            qrCodeTextLength > 0 && qrCodeTextLength <= 42,
            "INPUT_TEXT_INVALID"
        );
        require(hasLaunched && isPublicSaleActive, "PUBLIC_MINT_INACTIVE");
        require(totalSupply() + count <= MAX_SUPPLY, "MAX_SUPPLY_EXCEEDED");
        require(msg.value >= count * cost, "INCORRECT_ETH_AMOUNT");
        require(count > 0 && count <= MAX_COUNT_PER_TX, "MINT_COUNT_INCORRECT");
        require(count > 0, "MINT_COUNT_REQUIRED");

        _mint(qrCodeText, count);
    }

    /**
     * @notice The Team Mint is active at all time, but obviously limited to
     *         the Max Supply.
     *
     * @param qrCodeText The text the user wants in their QaRb Code, limited
     *                   to a maximum of 42 characters.
     * @param count      The number of QaRb Codes to mint. Limited to a certain
     *                   maximum per transaction.
     */
    function mintTeam(
        string memory qrCodeText,
        uint256 count
    ) external override onlyOwner {
        require(totalSupply() + count <= MAX_SUPPLY, "MAX_SUPPLY_EXCEEDED");
        require(count > 0, "MINT_COUNT_REQUIRED");
        uint256 qrCodeTextLength = bytes(qrCodeText).length;

        require(
            qrCodeTextLength > 0 && qrCodeTextLength <= 42,
            "INPUT_TEXT_INVALID"
        );
        _mint(qrCodeText, count);
    }

    function toggleLaunch() external override onlyOwner {
        hasLaunched = !hasLaunched;
    }

    /**
     * @notice Toggles the state of the Public Sale.
     *
     * @dev The public sale can be de-activated but the
     *      _mintedAtStartOfPublicSale can never be reset if the public sale is
     *      enabled for a 2nd (or more) times due to the Phases logic depending
     *      on the first toggle.
     */
    function togglePublicSaleActive() external override onlyOwner {
        isPublicSaleActive = !isPublicSaleActive;
        if (isPublicSaleActive) {
            isPhase2Active = true;
            if (!(_mintedAtStartOfPublicSale > 0))
                _mintedAtStartOfPublicSale = _tokenIds.current();
        }
    }

    function withdrawBalance(
        address payable to
    ) external override onlyOwner nonReentrant {
        require(address(this).balance > 0, "Contract has no balance");
        uint256 balance = address(this).balance;
        (bool success, ) = to.call{ value: balance }("");
        require(success, "Transfer failed");
    }

    function maxSupply() external view virtual override returns (uint256) {
        return MAX_SUPPLY;
    }

    function tokenQrCodeText(
        uint256 tokenId
    ) external view virtual override returns (string memory) {
        require(_exists(tokenId), "TOKEN_DOES_NOT_EXIST");
        return qrCodes[tokenId].text;
    }

    function whiteListSpots(
        address addr
    ) external view virtual override returns (uint256) {
        return _whiteList[addr];
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(_exists(tokenId), "TOKEN_DOES_NOT_EXIST");

        QrCodeStruct memory qrCode = qrCodes[tokenId];
        bytes memory svg = bytes(_generateQRCode(qrCode.text, qrCode.color));
        bytes memory title = abi.encodePacked(
            "#",
            Strings.toString(tokenId),
            " - ",
            qrCode.text
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                title,
                                '","description":"',
                                _TOKEN_DESCRIPTION,
                                '","image_data":"data:image/svg+xml;base64,',
                                Base64.encode(svg),
                                '","attributes":',
                                _textAttributesAsJSON(tokenId),
                                "}"
                            )
                        )
                    )
                )
            );
    }

    function totalSupply() public view virtual override returns (uint256) {
        return MAX_SUPPLY - _numAvailableTokens;
    }

    function currentMintPrice() public view override returns (uint256) {
        // This line should never take effect as this function is only called
        // from mint() which can only be called when in Phase 2 and onwards.
        if (!isPublicSaleActive) return PHASE_1_WHITELIST_MINT_PRICE;

        if (isPhase2Active) return PHASE_2_MINT_PRICE;
        if (isPhase3Active) return PHASE_3_MINT_PRICE;
        if (isPhase4Active) return PHASE_4_MINT_PRICE;
        if (isPhase5Active) return PHASE_5_MINT_PRICE;

        // Phase 6 should be active
        require(isPhase6Active, "PHASE_6_SHOULD_BE_ACTIVE");
        return PHASE_6_MINT_PRICE;
    }

    /**
     * @notice Executes the actual minting.
     *
     * @dev No conditions are checked here so please make sure this function is
     *      called from other functions that do the necessary enforcement of
     *      requirements.
     *
     * @param qrCodeText The text the user wants in their QaRb Code, limited
     *                   to a maximum of 42 characters.
     * @param count      The number of QaRb Codes to mint. Limited to a certain
     *                   maximum per transaction.
     */
    function _mint(string memory qrCodeText, uint256 count) private {
        uint256 updatedNumAvailableTokens = _numAvailableTokens;

        for (uint256 i; i < count; ++i) {
            _tokenIds.increment();
            uint256 newTokenId = _tokenIds.current();
            _mint(msg.sender, newTokenId);
            string memory color = _randomColor(newTokenId);
            QrCodeStruct memory qrCode = QrCodeStruct(qrCodeText, color);
            qrCodes[newTokenId] = qrCode;

            _updatePhase(newTokenId);
            --updatedNumAvailableTokens;
        }

        _numAvailableTokens = updatedNumAvailableTokens;
    }

    function _updatePhase(uint256 newTokenId) private {
        if (
            isPhase2Active &&
            newTokenId == _mintedAtStartOfPublicSale + PHASE_2_LIMIT
        ) {
            isPhase2Active = false;
            isPhase3Active = true;
            return;
        }

        if (
            isPhase3Active &&
            newTokenId ==
            _mintedAtStartOfPublicSale + PHASE_2_LIMIT + PHASE_3_LIMIT
        ) {
            isPhase3Active = false;
            isPhase4Active = true;
            return;
        }

        if (
            isPhase4Active &&
            newTokenId ==
            _mintedAtStartOfPublicSale +
                PHASE_2_LIMIT +
                PHASE_3_LIMIT +
                PHASE_4_LIMIT
        ) {
            isPhase4Active = false;
            isPhase5Active = true;
            return;
        }

        if (
            isPhase5Active &&
            newTokenId ==
            _mintedAtStartOfPublicSale +
                PHASE_2_LIMIT +
                PHASE_3_LIMIT +
                PHASE_4_LIMIT +
                PHASE_5_LIMIT
        ) {
            isPhase5Active = false;
            isPhase6Active = true;
        }
    }

    function _textAttributesAsJSON(
        uint256 tokenId
    ) private view returns (string memory json) {
        QrCodeStruct memory qrCode = qrCodes[tokenId];
        string memory attributeAsString = qrCode.text;
        string memory bgColorValue = qrCode.color;

        return
            string(
                abi.encodePacked(
                    '[{"trait_type":"Value", "value":"',
                    attributeAsString,
                    '"}, {"trait_type":"Background", "value":"#',
                    bgColorValue,
                    '"}]'
                )
            );
    }

    function _randomColor(
        uint256 tokenId
    ) private view returns (string memory) {
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.difficulty,
                    block.number,
                    tokenId
                )
            )
        );

        uint8 count = 0;
        uint8 r = uint8(random >> (0 * 8));
        if (r < 128) {
            count++;
        }
        uint8 g = uint8(random >> (1 * 8));
        if (g < 128) {
            count++;
        }
        uint8 b = uint8(random >> (2 * 8));
        if (b < 128) {
            count++;
        }

        if (count >= 2) {
            uint8 max = _max(r, g, b);
            if (r == max) {
                r = 255;
            } else if (g == max) {
                g = 255;
            } else {
                b = 255;
            }
        }

        bytes memory color = new bytes(3);
        color[0] = r < 50 ? bytes1(uint8(50)) : bytes1(r);
        color[1] = g < 50 ? bytes1(uint8(50)) : bytes1(g);
        color[2] = b < 50 ? bytes1(uint8(50)) : bytes1(b);

        return _bytesToHexString(color);
    }

    function _max(uint8 a, uint8 b, uint8 c) private pure returns (uint8) {
        if (a >= b && a >= c) {
            return a;
        } else if (b >= a && b >= c) {
            return b;
        } else {
            return c;
        }
    }

    function _bytesToHexString(
        bytes memory data
    ) private pure returns (string memory) {
        bytes memory hexAlphabet = "0123456789abcdef";
        bytes memory result = new bytes(2 * data.length);
        for (uint256 i = 0; i < data.length; i++) {
            result[2 * i] = hexAlphabet[uint8(data[i] >> 4)];
            result[2 * i + 1] = hexAlphabet[uint8(data[i] & 0x0f)];
        }
        return string(result);
    }
}

