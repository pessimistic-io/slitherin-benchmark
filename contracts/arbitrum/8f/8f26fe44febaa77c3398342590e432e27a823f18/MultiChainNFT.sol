// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721.sol";
import "./IERC2981.sol";
import "./IMasterContract.sol";

/**
 * Used to delegate ownership of a contract to another address, to save on unneeded transactions to approve contract use for users
 */
interface IProxyRegistry {
    function proxies(address) external returns (address);
}

contract MultiChainNFT is Ownable, ERC721, IERC2981, IMasterContract {
    event LogSetRoyalty(uint16 royaltyRate, address indexed royaltyReceiver_);

    uint256 private BPS = 10_000;

    uint256 public totalSupply;
    mapping (uint256 => string) private tokenURI_;

    struct RoyaltyData {
        address royaltyReceiver;
        uint16 royaltyRate;
    }

    RoyaltyData public royaltyInformation;

    bool public immutability = false;

    constructor () ERC721("MASTER", "MASTER") {}

    address minter;

    modifier onlyMinter {
        require(msg.sender == minter);
        _;
    }
    function init(bytes calldata data) public payable override {
        (string memory _name, string memory _symbol, address owner_, address minter_) = abi.decode(data, (string, string, address, address));
        require(bytes(symbol).length == 0, "already initialized");
        _transferOwnership(owner_);
        minter = minter_;
        name = _name;
        symbol = _symbol;
    }

    function mintWithId(address to, uint256 tokenId, string calldata _tokenURI) external onlyMinter {
        totalSupply++;
        tokenURI_[tokenId] = _tokenURI;
        _mint(to, tokenId);
    }

    function burn(uint256 id) external {
        address oldOwner = _ownerOf[id];

        require(
            msg.sender == minter || msg.sender == oldOwner || msg.sender == getApproved[id] || isApprovedForAll[oldOwner][msg.sender],
            "NOT_AUTHORIZED"
        );

        _burn(id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return tokenURI_[id];
    }

    /// @notice Called with the sale price to determine how much royalty is owed and to whom.
    /// @param _tokenId - the NFT asset queried for royalty information
    /// @param _salePrice - the sale price of the NFT asset specified by _tokenId
    /// @return receiver - address of who should be sent the royalty payment
    /// @return royaltyAmount - the royalty payment amount for _salePrice
    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) external view override returns (
        address receiver,
        uint256 royaltyAmount
    ) {
        return (royaltyInformation.royaltyReceiver, _salePrice * royaltyInformation.royaltyRate / BPS);
    }

    function setRoyalty(address royaltyReceiver_, uint16 royaltyRate_) external onlyMinter {
        require(royaltyReceiver_ != address(0));
        royaltyInformation = RoyaltyData(royaltyReceiver_, royaltyRate_);
        emit LogSetRoyalty(royaltyRate_, royaltyReceiver_);
    }

    function supportsInterface(bytes4 interfaceId) public view override (ERC721, IERC165) returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x2a55205a || // ERC165 Interface ID for IERC2981 
            interfaceId == 0x5b5e139f;  // ERC165 Interface ID for ERC721Metadata;
    }
}

