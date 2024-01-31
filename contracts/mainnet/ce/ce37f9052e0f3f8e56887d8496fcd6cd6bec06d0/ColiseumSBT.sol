// SPDX-License-Identifier: MIT

/* @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@&#BG5G#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@&BG555GYB#P#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@#P55YGBBGPG@&PB@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@&B5YPBG5BB&#P@@@&5PGB@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@BYYPYGYGP@@@B5BBBGGPYYB@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@PJJ5G5B5B5BPPPPPPPPPP55G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@57YYG@5BBP5P5PP5GGGPPGP5P@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@G!?JYBGY5P55GGPPGGPPGYBG#5G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@P~5PYY555PPPPP5YBYY#@GBB&&5#&#BB&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@G!YJY55YY5YPYY#PBP5#&555##GGBPPJ5#@@@@#&#B&G#########&&&&&@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@G7JYJY55YYJGP5BYYGGGGPGPGGGGGGG55YB###B##BBB&&&##@@@#PGB&&###&&&@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@G7?J5Y55P5JYPPPPPGGGGGPGBBBB#BBP5BG#####B###BB##P&@@&GGP&@@@&YG####&@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@?!JYY5YYPPPPGGGPG#BBGBB#BGY?J5#G55###&BGB&#B##BGP@###@@P#####GG#@BBG##&@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@Y?JYJ55PPGPBBG5GBPP7^J#PY!:.:5#G#5G5J5#B#Y!~7P#BG##&#@&G#G5G#@BG&PGG@B5B@@@@@@@@@@@@@@
@@@@@@@@@@@@@@G?Y555PPP5GP5J^PP5J..5#G5^.::G#B&&7.^~Y#Y!J?^^5BGGB@BYG#&BPB@&###GB#BGPP&@@@@@@@@@@@@@
@@@@@@@@@@@@@&JJJYYY5Y57P5P7:BBPJ..YBG5^::^PPP#&P~GB5GY&@@G^P#B&Y#!.!PB^?GB5G#G#&##BGY&@@@@@@@@@@@@@
@@@@@@@@@@@@@#7?JY55PPP75PP?~55P5JY55PBGGBBPPP#####BGGYPGBPPPBB&B#7^7GB.!G5^YP!555PPG5#@@@@@@@@@@@@@
@@@@@@@@@@@@@@5JYYY5Y5G5YPBBGPPBBBBGPGGBGBGGGGGBBBBBBBP5@@@G&@@@@@@@&P#:!BP:5G7PY55YJ7#@@@@@@@@@@@@@
@@@@@@@@@@@@@@J?JY5G5PGGPPGGGGPGGGBGGGBBBB#BGG####B#GGP5###G#&#&&&&&#P#GBBBPGB5GPPP557#@@@@@@@@@@@@@
@@@@@@@@@@@@@#?5PPPPPPPGPGBGGGG#BPPBB##G5JPBB&&PJ?JGB#B5GGB&#G##GB&BPP###B###B#BBBGGP?B@@@@@@@@@@@@@
@@@@@@@@@@@@@@YJYY55P55YGPPJ~GB5Y^:J#G57..^Y#BY:...!5#PJ::^?BBP^:^5BBG&7J##?G#YGGPGGGYB@@@@@@@@@@@@@
@@@@@@@@@@@@@@5JYY5YP557P55~:GG5J.:Y#P5^:::G#BJ:::.~B#B#?.::Y#J.:.?GBGG.!BP:5G7GY5P5Y?B@@@@@@@@@@@@@
@@@@@@@@&&&&&&YJY55PGPP7PPP!:BBPJ::5#GP~:::B#BJ:::.~##B&@!.:5#Y.::JGB#P.!BP:5G7PY555YJB&&&&&@@@@@@@@
@@@@@@@@&&&&&&BPPP5P55P?55P!:GGPJ..Y#GP^..:B#BJ....~##B&@#~:5#J...?GGB#!?GP?PG5GGBBB##&&&&&@@@@@@@@@
@@@@@@@@@@@@&&&&&&&&####BBBBGGGGPYYPPPPJ???PPPY777!?GPGB##PJPGP555GBBBB####&&&&&&&&&&&&@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@&&&&&&&&&&&&&&&####&&&#################&###&&&&&&&&&&&&&&&&&@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@R@@@ */

pragma solidity ^0.8.13;

import "./Strings.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./DefaultOperatorFilterer.sol";
import "./ERC721A.sol";
import "./IERC721A.sol";

contract ColiseumSBT is ERC721A, Ownable, DefaultOperatorFilterer {
    using Strings for uint256;
    using SafeMath for uint256;

    // Custom errors
    error SoulBoundTokensMayOnlyBeBurned();
    error NotAController();

    // State variables
    uint256 public soulBoundedAmount = 0;
    string private _baseTokenURI =
        "https://nftstorage.link/ipfs/bafybeicksu2nga5i2kwuc5wu2ovbsouwsaisgdyp2rhtrkfu7augoen76y/";
    bool public soulBoundLockActive = false;

    // Mappings
    mapping(address => bool) private _controller;
    mapping(uint256 => uint8) private _tokenToTier;

    // Constructor
    constructor() ERC721A("ColiseumSBT", "SBTColiseum") {
        _controller[msg.sender] = true;
    }

    // Modifiers
    modifier onlyController() {
        if (_controller[msg.sender] == false) revert NotAController();
        _;
    }

    // Functions

    /**
     * @dev Allows the controller to set the tier for multiple tokens.
     * @param _tokenIds Array of token IDs.
     * @param _tokenTier The tier to set for the tokens.
     */
    function setTierForTokens(
        uint256[] calldata _tokenIds,
        uint8 _tokenTier
    ) external onlyController {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _tokenToTier[_tokenIds[i]] = _tokenTier;
        }
    }

    /**
     * @dev Allows the controller to set the tier for a single token.
     * @param _tokenId The token ID.
     * @param _tokenTier The tier to set for the token.
     */
    function setTierForToken(
        uint256 _tokenId,
        uint8 _tokenTier
    ) external onlyController {
        _tokenToTier[_tokenId] = _tokenTier;
    }

    /**
     * @dev Allows the controller to set the tiers for multiple tokens at once.
     * @param _tokenIds An array of token IDs.
     * @param _tokenTier An array of tiers corresponding to each token ID in _tokenIds.
     */
    function setTiersForTokens(
        uint256[] calldata _tokenIds,
        uint8[] calldata _tokenTier
    ) external onlyController {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _tokenToTier[_tokenIds[i]] = _tokenTier[i];
        }
    }

    /**
     * @dev Mints a token and assigns it to a given address.
     * @param soulBounder The address to receive the minted token.
     */
    function soulBound(address soulBounder) external {
        require(
            (_controller[msg.sender] == true) || (owner() == _msgSender()),
            "Caller is not authorized"
        );
        _mint(soulBounder, 1);
        _tokenToTier[totalMinted()] = 2;
        soulBoundedAmount++;
    }

    /**
     * @dev Mints tokens and assigns them to multiple addresses in one function call.
     * @param targets An array of addresses to receive the minted tokens.
     */
    function airDrop(address[] calldata targets) external {
        require(
            (_controller[msg.sender] == true) || (owner() == _msgSender()),
            "Caller is not authorized"
        );
        for (uint256 i = 0; i < targets.length; i++) {
            _mint(targets[i], 1);
            _tokenToTier[totalMinted()] = 2;
        }
        soulBoundedAmount += targets.length;
    }

    /**
     * @notice Allows the controller to transfer a token on behalf of the owner
     * @dev This function can only be called by the controller
     * @param from The address of the current owner of the token
     * @param to The address to receive the token
     * @param tokenId The ID of the token to be transferred
     */
    function controllerTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external onlyController {
        require(to != address(0), "Invalid recipient address");

        safeTransferFrom(from, to, tokenId);
    }

    /**
     * @dev Burns multiple tokens at once.
     * @param tokenIds An array of token IDs to burn.
     */
    function burn(uint256[] calldata tokenIds) external onlyController {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _burn(tokenIds[i]);
        }
        soulBoundedAmount -= tokenIds.length;
    }

    /**
     * @dev Returns the base URI for a given token.
     * @return The base URI.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Sets the base URI for the token metadata.
     * @param baseURI The new base URI.
     */
    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    /**
     * @dev Toggles the lock state of Soulbound tokens.
     */
    function toggleSoulboundLock() external onlyOwner {
        soulBoundLockActive = !soulBoundLockActive;
    }

    /**
     * @dev Adds multiple addresses as controllers in the contract.
     * @param _addresses An array of addresses to be added as controllers.
     */
    function addControllers(address[] calldata _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _controller[_addresses[i]] = true;
        }
    }

    /**
     * @dev Removes multiple addresses from being controllers in the contract.
     * @param _addresses An array of addresses to be removed as controllers.
     */
    function removeControllers(
        address[] calldata _addresses
    ) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _controller[_addresses[i]] = false;
        }
    }

    /**
     * @dev Checks if a given address is a controller.
     * @param _address The address to be checked.
     * @return bool True if the address is a controller, false otherwise.
     */
    function isController(address _address) external view returns (bool) {
        return _controller[_address];
    }

    /**
     * @dev Returns the tier of a given token.
     * @param _tokenId The token ID.
     * @return The tier of the token.
     */
    function getTokenTier(uint256 _tokenId) public view returns (uint8) {
        return _tokenToTier[_tokenId];
    }

    /**
     * @dev Hooks into the token transfer process and enforces restrictions.
     * @param from The address sending the tokens.
     * @param to The address receiving the tokens.
     * @param startTokenId The ID of the first token being transferred.
     * @param quantity The number of tokens being transferred.
     */
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        require(
            !soulBoundLockActive || _controller[msg.sender],
            "Transfers are locked"
        );
    }

    /**
     * @dev Transfers a token from one address to another.
     * @param from The address sending the token.
     * @param to The address receiving the token.
     * @param tokenId The ID of the token being transferred.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    /**
     * @dev Transfers a token from one address to another.
     * @param from The address sending the token.
     * @param to The address receiving the token.
     * @param tokenId The ID of the token being transferred.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    /**
     * @dev Transfers a token from one address to another.
     * @param from The address sending the token.
     * @param to The address receiving the token.
     * @param tokenId The ID of the token being transferred.
     * @param data Additional data to pass with the transfer.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}

