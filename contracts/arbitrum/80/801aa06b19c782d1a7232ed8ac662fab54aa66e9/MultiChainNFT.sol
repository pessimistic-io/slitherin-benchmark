// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./ERC721.sol";
import {IERC2981} from "./IERC2981.sol";
import "./IMasterContract.sol";
import "./Strings.sol";
import "./ONFT721Core.sol";


contract MultiChainNFT is ONFT721Core, ERC721, IERC2981, IMasterContract {
    using Strings for uint256;

    event LogSetRoyalty(uint16 royaltyRate, address indexed royaltyReceiver_);
    event LogChangeBaseURI(string baseURI, bool immutability_);


    uint256 private constant BPS = 10_000;

    uint256 public totalSupply;

    string public baseURI;
    bool public immutability = false;

    struct RoyaltyData {
        address royaltyReceiver;
        uint16 royaltyRate;
    }

    RoyaltyData public royaltyInformation;

    constructor (uint256 _minGasToTransfer, address _lzEndpoint) ONFT721Core(_minGasToTransfer, _lzEndpoint) ERC721("MASTER", "MASTER") {}
    
    // TODO: overwrite transfer behavior
    /// @notice Transfers ownership to `newOwner`. Either directly or claimable by the new pending owner.
    /// Can only be invoked by the current `owner`.
    /// @param newOwner Address of the new owner.
    /// @param direct True if `newOwner` should be set immediately. False if `newOwner` needs to use `claimOwnership`.
    /// @param renounce Allows the `newOwner` to be `address(0)` if `direct` and `renounce` is True. Has no effect otherwise.
    function transferOwnership(
        address newOwner,
        bool direct,
        bool renounce
    ) public override onlyOwner {
        if (direct) {
            // Checks
            require(newOwner != address(0) || renounce, "Ownable: zero address");

            // Effects
            emit OwnershipTransferred(owner, newOwner);
            owner = newOwner;
            pendingOwner = address(0);
        } else {
            // Effects
            pendingOwner = newOwner;
        }
    }


    function init(bytes calldata data) public payable override {
        (string memory _name, string memory _symbol, string memory _baseURI, address owner_, uint16[] memory chains, bytes[] memory remotes) = abi.decode(data, (string, string, string, address, uint16[], bytes[]));
        require(bytes(symbol).length == 0, "already initialized");
        for (uint i; i < chains.length; i++) {
            _setTrustedRemote(chains[i], remotes[i]);
        }
        // Effects
        emit OwnershipTransferred(address(0), owner_);
        owner = owner_;
        baseURI = _baseURI;
        name = _name;
        symbol = _symbol;
    }

    function _debitFrom(address _from, uint16, bytes memory, uint _tokenId) internal virtual override {
        _burn(_tokenId);
    }

    function _creditTo(uint16, address _toAddress, uint _tokenId) internal virtual override {
        _mintWithId(_toAddress, _tokenId);
    }

    function _mintWithId(address to, uint256 tokenId) internal {
        totalSupply++;
        _mint(to, tokenId);
    }

    function mintWithId(address to, uint256 tokenId) external onlyOwner {
        _mintWithId(to, tokenId);
    }

    function burn(uint256 id) public {
        address oldOwner = _ownerOf[id];

        require(
            msg.sender == oldOwner || msg.sender == getApproved[id] || isApprovedForAll[oldOwner][msg.sender],
            "NOT_AUTHORIZED"
        );

        _burn(id);
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
        receiver = royaltyInformation.royaltyReceiver;
        royaltyAmount = (_salePrice * uint256(royaltyInformation.royaltyRate)) / BPS;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, id.toString()))
                : "";
    }

    function changeBaseURI(string memory baseURI_, bool immutability_)
        external
        onlyOwner
    {
        require(immutability == false, "Immutable");
        immutability = immutability_;
        baseURI = baseURI_;

        emit LogChangeBaseURI(baseURI_, immutability_);
    }


    function setRoyalty(address royaltyReceiver_, uint16 royaltyRate_) external onlyOwner {
        require(royaltyReceiver_ != address(0));
        royaltyInformation = RoyaltyData(royaltyReceiver_, royaltyRate_);
        emit LogSetRoyalty(royaltyRate_, royaltyReceiver_);
    }

    function supportsInterface(bytes4 interfaceId) public view override (ONFT721Core, ERC721) returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x2a55205a || // ERC165 Interface ID for IERC2981 
            interfaceId == 0x5b5e139f || // ERC165 Interface ID for ERC721Metadata;
            super.supportsInterface(interfaceId);  
    }
}

