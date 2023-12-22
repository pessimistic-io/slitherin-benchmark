// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./RandomlyAssigned.sol";

contract PeopleNft is
    Initializable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    RandomlyAssigned
{
    using StringsUpgradeable for uint256;

    uint256 public maxSupply;

    string public baseURI;
    string public baseExtension;

    bool public isBurnEnabled;
    bool public paused;
            
    uint256 public mintPrice;
    

    function initialize() public initializer
    {
        __ERC721_init("People 3000 AD", "GENESIS");
        __ERC721Enumerable_init();
        __Ownable_init();
        __RandomlyAssigned_init(3000, 0);

        mintPrice = 0.058 ether;
        maxSupply = 3000;
        baseExtension = ".json";
        isBurnEnabled = false;
        paused = true;
    }

    function changePauseState() public onlyOwner {
        paused = !paused;
    }
    
    function setMintPrice(uint256 _mintPrice) public onlyOwner {
        mintPrice = _mintPrice;
    }
    
    function setBaseURI(string calldata _tokenBaseURI) external onlyOwner {
        baseURI = _tokenBaseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setIsBurnEnabled(bool _isBurnEnabled) external onlyOwner {
        isBurnEnabled = _isBurnEnabled;
    }

    function withdraw(address _treasury) public onlyOwner {
        // require(totalNFT >= 3000, "GENESIS: Withdraw is available after sold out");

        uint256 balance = address(this).balance;
        AddressUpgradeable.sendValue(payable(_treasury), balance);
    }

    function mintGENISIS(uint256 _amount) public payable {
        require(!paused, "GENESIS: contract is paused");
        require(_amount > 0, "GENESIS: zero amount");
        require(mintPrice * _amount <= msg.value, "GENESIS: Insufficient Fund");

        for (uint256 ind = 0; ind < _amount; ind++) {
            _mintRandomId(msg.sender);
        }
    }

    function mintForOwner(uint256 _amount) public onlyOwner {
        require(!paused, "GENESIS: contract is paused");
        require(_amount > 0, "GENESIS: zero amount");

        for (uint256 ind = 0; ind < _amount; ind++) {
            _mintRandomId(msg.sender);
        }
    }

    function mintForOwnerWithIDs(uint256[] memory _ids) public onlyOwner {
        require(_ids.length > 0, "GENESIS: zero amount");

        for (uint256 i = 0; i < _ids.length; i++) {
            require(!_exists(_ids[i]),"GENESIS: toked ID is already exist");
            _safeMint(msg.sender, _ids[i]);
        }
    }

    function _mintRandomId(address to) internal {
		uint256 id = nextToken();
		require(id > 0 && id <= maxSupply, "Mint not possible");
		_safeMint(to, id);
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
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        baseExtension
                    )
                )
                : "";
    }

    function setBaseExtension(string memory _newBaseExtension)
        public
        onlyOwner
    {
        baseExtension = _newBaseExtension;
    }

    function burn(uint256 tokenId) external {
        require(isBurnEnabled, "GENESIS : burning disabled");
        require(
            _isApprovedOrOwner(msg.sender, tokenId),
            "GENESIS : burn caller is not owner nor approved"
        );
        _burn(tokenId);
    }

    receive() external payable {}
}
