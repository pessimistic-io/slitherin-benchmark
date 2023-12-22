//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";

contract L2NFT is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    using Strings for uint256;

    address public coreMinter;

    uint256 public maxSupply;
    uint256 public nextTokenId;
    uint256 public maxAdminMints;
    uint256 private adminMints;

    string public baseURI;

    mapping(address => bool) addressMinted;

    function initialize(
        address _coreMinter,
        uint256 _maxSupply,
        uint256 _maxAdminMints,
        string memory _name,
        string memory _symbol
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __ERC721Enumerable_init_unchained();
        __Ownable_init_unchained();
        coreMinter = _coreMinter;
        maxSupply = _maxSupply;
        maxAdminMints = _maxAdminMints;
        nextTokenId = 1;
        adminMints = 1;
    }

    /**
     * Mint an NFT
     * Callable only by core minter contract
     * Any address may mint up to 1 NFT
     */
    function mint(address to) external onlyCoreMinter {
        require(!addressMinted[to], "Address already minted");
        require(nextTokenId <= maxSupply - maxAdminMints, "Mint cap hit");

        addressMinted[to] = true;
        _mint(to, nextTokenId);

        nextTokenId++;
    }

    /**
     * Mint an NFT by owner of core minter contract
     * Callable only by core minter contract
     * Owner may mint up to *maxAdminMints* NFTs
     */
    function adminMint(address to) external onlyCoreMinter {
        require(adminMints <= maxAdminMints, "Admin can mint up to maxAdminMints NFTs");

        _mint(to, nextTokenId);

        adminMints++;
        nextTokenId++;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory currentBaseURI = _baseURI();
        return string(abi.encodePacked(currentBaseURI, tokenId.toString(), ".json"));
    }

    modifier onlyCoreMinter {
        require(msg.sender == coreMinter, "Only core minter can mint");
        _;
    }
}

