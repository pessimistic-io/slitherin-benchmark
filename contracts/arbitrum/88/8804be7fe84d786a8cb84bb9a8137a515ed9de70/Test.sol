pragma solidity ^0.8.20;

import "./ERC721.sol";
import "./Base64.sol";
import "./IVePostNFTSVG.sol";

contract Test is ERC721 {
    IVePostNFTSVG public vePostNFTSVG;

    uint256 public tokenId;
    uint8 public typeVe;
    uint256 public start;
    uint256 public end;
    uint256 public current;
    uint256 public boost;
    uint256 public weight;

    constructor() ERC721("Mock NFT", "VEMNFT") {}

    function mint(address to) public {
        ++tokenId;
        uint _tokenId = tokenId;
        _mint(to, _tokenId);
    }

    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        return
            vePostNFTSVG.buildVePost(
                tokenId,
                typeVe,
                start,
                end,
                current,
                boost,
                weight
            );
    }

    function set(
        uint256 _tokenId,
        uint8 _typeVe,
        uint256 _start,
        uint256 _end,
        uint256 _current,
        uint256 _boost,
        uint256 _weight
    ) public {
        tokenId = _tokenId;
        typeVe = _typeVe;
        start = _start;
        end = _end;
        current = _current;
        boost = _boost;
        weight = _weight;
    }
    function setVePostNFTSVG(IVePostNFTSVG _vePostNFTSVG) public {
        vePostNFTSVG = _vePostNFTSVG;
    }
}

