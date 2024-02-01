pragma solidity ^0.7.3;

import "./Ownable.sol";
import "./ERC721.sol";
import "./AccessControl.sol";
import "./Minting.sol";
import "./String.sol";

contract Cosmetic is ERC721, AccessControl, Ownable {
    mapping(uint256 => uint16) cosmeticProtos;

    event CosmeticMinted(
        address to,
        uint256 amount,
        uint256 tokenId,
        uint16  proto
    );

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    constructor(string memory baseURI)
        ERC721("Gods Unchained Cosmetic", "GU")
    {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        string memory uri = string(abi.encodePacked(
            baseURI,
            String.fromAddress(address(this)),
            "/"
        ));

        super._setBaseURI(uri);
    }

    function mintFor(
        address to,
        uint256 amount,
        bytes memory mintingBlob
    ) public onlyAdmin {
        (uint256 tokenId, uint16 proto) = Minting.deserializeMintingBlob(mintingBlob);
        super._mint(to, tokenId);
        cosmeticProtos[tokenId] = proto;

        emit CosmeticMinted(to, amount, tokenId, proto);
    }

    function burn(uint256 tokenId) public onlyAdmin {
        super._burn(tokenId);
    }

    /**
     * @dev Retrieve the proto and quality for a particular card represented by it's token id
     *
     * @param tokenId the id of the card you'd like to retrieve details for
     * @return proto The proto of the specified card
     */
    function getDetails(
        uint256 tokenId
    )
        public
        view
        returns (uint16 proto)
    {
        return (cosmeticProtos[tokenId]);
    }

}

