// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./MerkleProof.sol";
import "./IERC2981.sol";
import "./console.sol";

contract Nightwalkers is ERC721A, Ownable, ReentrancyGuard {
    uint256 public constant TOTAL_SUPPLY = 2222;
    uint256 public guestListMinted;
    mapping (address => uint256) whitelistMinted;
    address public guestAddress;
    address public treasuryAddress;
    string private _baseUri;
    bytes public encryptedUri;
    bytes32 public whitelistRoot;

    // Setting for the guest phase
    uint256 public guestStartTime;
    uint256 public guestEndTime;
    uint256 public maxAmountPerGuest;

    // Setting for whitelist
    uint256 public maxAmountPerWhitelist;
    uint256 public whitelistStartTime;
    uint256 public whitelistEndTime;
    uint256 public whitelistMintPrice;

    // Setting for public
    uint256 public publicStartTime;
    uint256 public publicMintPrice;

    /// @dev Object with royalty info
    struct RoyaltyInfo {
        address receiver;
        uint96 royaltyFraction;
    }

    event GuestMinted(address indexed user, uint256 quantity);
    event WhitelistMinted(address indexed user, uint256 quantity);
    event PublicMinted(address indexed user, uint256 quantity);


    /// @dev Fallback royalty information
    RoyaltyInfo private _defaultRoyaltyInfo;

    /// @dev Royalty information
    mapping(uint256 => RoyaltyInfo) private _tokenRoyaltyInfo;

    constructor(
        uint256 guestStartTime_,
        uint256 guestEndTime_,
        address guestAddress_,
        uint256 whitelistStartTime_,
        uint256 whitelistEndTime_,
        uint256 whitelistMintPrice_,
        bytes32 whitelistRoot_,
        uint256 publicStartTime_,
        uint256 publicMintPrice_,
        address treasuryAddress_,
        bytes memory encryptedUri_
    ) ERC721A("Nightwalkers", "NW") {
        require(guestEndTime_ > guestStartTime_, "Invalid guest time");
        require(whitelistEndTime_ > whitelistStartTime_, "Invalid whitelist time");
        require(guestEndTime_ <= whitelistStartTime_, "Whitelist overlay guest");
        require(whitelistEndTime <= publicStartTime, "Public overlay whitelist");

        guestStartTime = guestStartTime_;
        guestEndTime = guestEndTime_;
        maxAmountPerGuest = 33;
        guestAddress = guestAddress_;
        whitelistStartTime = whitelistStartTime_;
        whitelistEndTime = whitelistEndTime_;
        whitelistMintPrice = whitelistMintPrice_;
        maxAmountPerWhitelist = 5;
        whitelistRoot = whitelistRoot_;

        publicStartTime = publicStartTime_;
        publicMintPrice = publicMintPrice_;

        treasuryAddress = treasuryAddress_;
        encryptedUri = encryptedUri_;
        _setDefaultRoyalty(treasuryAddress, 500);
        _baseUri = "ipfs://QmS95rDFb9LbSwaxpF9mKUWzNZL531KjzbhVPqUVKmYS6x/";
    }

    function mint(uint256 quantity, bytes32[] memory proof) external payable nonReentrant {
        require(totalSupply() + quantity <= TOTAL_SUPPLY, "Total exceed");
        uint256 currentTime = block.timestamp;
        if (currentTime >= guestStartTime && currentTime < guestEndTime) {
            _mintGuest(quantity);
        } else if (currentTime >= whitelistStartTime && currentTime < whitelistEndTime) {
            _mintWhitelist(quantity, proof);
        } else if (currentTime >= publicStartTime) {
            _mintPublic(quantity);
        } else {
            revert("Not allowed to mint this time");
        }
    }

    function _mintGuest(uint256 quantity) private {
        require(quantity + guestListMinted <= maxAmountPerGuest, "Guest exceed");
        require(msg.sender == guestAddress, "Not guest"); 
        guestListMinted += quantity;
        _safeMint(msg.sender, quantity);
        emit GuestMinted(msg.sender, quantity);
    }

    function _mintWhitelist(uint256 quantity, bytes32[] memory proof) private {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(proof, whitelistRoot, leaf), "Not whitelisted");
        require(msg.value >= whitelistMintPrice * quantity, "Not enough money");
        require(quantity + whitelistMinted[msg.sender] <= maxAmountPerWhitelist, "Whitelist exceed");
        whitelistMinted[msg.sender] += quantity;
        _safeMint(msg.sender, quantity);
        emit WhitelistMinted(msg.sender, quantity);
    }

    function _mintPublic(uint256 quantity) private {
        require(msg.value >= publicMintPrice * quantity, "Not enough money");
        _safeMint(msg.sender, quantity);
        emit PublicMinted(msg.sender, quantity);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns how much royalty is owed and to whom, based on a sale price that may be denominated in any unit of
     * exchange. The royalty amount is denominated and should be payed in that same unit of exchange.
     */
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        external
        view
        returns (address, uint256)
    {
        RoyaltyInfo memory royalty = _tokenRoyaltyInfo[_tokenId];

        if (royalty.receiver == address(0)) {
            royalty = _defaultRoyaltyInfo;
        }

        uint256 royaltyAmount = (_salePrice * royalty.royaltyFraction) /
            _feeDenominator();

        return (royalty.receiver, royaltyAmount);
    }

    //Admin function

    function withdraw() external onlyOwner {
        (bool os,) = payable(treasuryAddress).call{ value: address(this).balance}("");
        require(os);
    }


    function setTresasuryAddress(address treasury) external onlyOwner {
        require(treasury != address(0), "Zero address");
        treasuryAddress = treasury;
    }

    function setWhitelistRoot(bytes32 root_) external onlyOwner {
        whitelistRoot = root_;
    }

    function setWhitelistConfig(
        uint256 whitelistStartTime_,
        uint256 whitelistEndTime_,
        uint256 whitelistMintPrice_,
        uint256 maxAmountPerWhitelist_
    ) external onlyOwner {
        whitelistStartTime = whitelistStartTime_;
        whitelistEndTime = whitelistEndTime_;
        whitelistMintPrice = whitelistMintPrice_;
        maxAmountPerWhitelist = maxAmountPerWhitelist_;
    }

    function setPublicConfig(
        uint256 publicStartTime_,
        uint256 publicMintPrice_
    ) external onlyOwner {
        publicStartTime = publicStartTime_;
        publicMintPrice = publicMintPrice_;
    }

    function reveal(bytes calldata key) external onlyOwner {
        require(encryptedUri.length > 0, "Already reveal");
        _baseUri = string(encryptDecrypt(encryptedUri, key));
        encryptedUri = "";
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    function setBaseURI(string memory baseUri_) external onlyOwner {
        _baseUri = baseUri_;
    }
        /**
     *  @notice         Encrypt/decrypt data on chain.
     *  @dev            Encrypt/decrypt given `data` with `key`. Uses inline assembly.
     *                  See: https://ethereum.stackexchange.com/questions/69825/decrypt-message-on-chain
     *
     *  @param data     Bytes of data to encrypt/decrypt.
     *  @param key      Secure key used by caller for encryption/decryption.
     *
     *  @return result  Output after encryption/decryption of given data.
     */
    function encryptDecrypt(bytes memory data, bytes calldata key) private pure returns (bytes memory result) {
        // Store data length on stack for later use
        uint256 length = data.length;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Set result to free memory pointer
            result := mload(0x40)
            // Increase free memory pointer by lenght + 32
            mstore(0x40, add(add(result, length), 32))
            // Set result length
            mstore(result, length)
        }

        // Iterate over the data stepping by 32 bytes
        for (uint256 i = 0; i < length; i += 32) {
            // Generate hash of the key and offset
            bytes32 hash = keccak256(abi.encodePacked(key, i));

            bytes32 chunk;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // Read 32-bytes data chunk
                chunk := mload(add(data, add(i, 32)))
            }
            // XOR the chunk with hash
            chunk ^= hash;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // Write 32-byte encrypted chunk
                mstore(add(result, add(i, 32)), chunk)
            }
        }
    }

    // Internal functions


    /**
     * @dev The denominator with which to interpret the fee set in {_setTokenRoyalty} and {_setDefaultRoyalty} as a
     * fraction of the sale price. Defaults to 10000 so fees are expressed in basis points, but may be customized by an
     * override.
     */
    function _feeDenominator() internal pure returns (uint96) {
        return 10000;
    }

    /**
     * @dev Sets the royalty information that all ids in this contract will default to.
     *
     * Requirements:
     *
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function _setDefaultRoyalty(address receiver, uint96 feeNumerator)
        internal
    {
        require(feeNumerator <= _feeDenominator(), "fee exceed salePrice");
        require(receiver != address(0), "invalid receiver");

        _defaultRoyaltyInfo = RoyaltyInfo(receiver, feeNumerator);
    }
}
