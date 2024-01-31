
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
import "./Ownable.sol";
import "./Strings.sol";
import "./ERC721A.sol";


contract Kyberpunk is ERC721A, Ownable {
    using Strings for uint256;

    address private constant teamAddress = 0x2799e45f9A28eddABdEE3EB77A05373FB2841f9b;

    uint256 public constant maxSupply = 222;
    uint256 public constant claimAmount = 11;

    uint256 public TOTAL_FREE_SUPPLY = 0;

    uint256 public  maxPerTxn = 2;
    uint256 public  maxPerWallet = 2;

    bool claimed = false;

    uint256 public token_price = 0.006 ether;
    bool public publicSaleActive;
    bool public freeMintActive;

    uint256 public freeMintCount;

    mapping(address => uint256) public freeMintClaimed;

    string private _baseTokenURI;


    constructor() ERC721A("Kyberpunk", "KP") {
        _safeMint(msg.sender, 6);
    }


    modifier underMaxSupply(uint256 _quantity) {
        require(
            _totalMinted() + _quantity <= maxSupply,
            "Mint would exceed max supply"
        );

        _;
    }

    modifier validateFreeMintStatus() {
        require(freeMintActive, "free claim is not active");
        require(freeMintCount + 1 <= TOTAL_FREE_SUPPLY, "Purchase would exceed max supply of free mints");
        require(freeMintClaimed[msg.sender] == 0, "wallet has already free minted");
        
        _;
    }

    modifier validatePublicStatus(uint256 _quantity) {
        require(publicSaleActive, "Sale hasn't started");
        require(msg.value >= token_price * _quantity, "Need to send more ETH.");
        require(_quantity > 0 && _quantity <= maxPerTxn, "Invalid mint amount.");
        require(
            _numberMinted(msg.sender) + _quantity <= maxPerWallet,
            "This purchase would exceed maximum allocation for public mints for this wallet"
        );

        _;
    }

    /**
     * @dev override ERC721A _startTokenId()
     */
    function _startTokenId() 
        internal 
        view 
        virtual
        override 
        returns (uint256) {
        return 1;
    }

    function freeMint() 
        external 
        validateFreeMintStatus
        underMaxSupply(1)
    {
        freeMintClaimed[msg.sender] = 1;
        freeMintCount++;

        _mint(msg.sender, 1, "", false);
    }

    function mint(uint256 _quantity)
        external
        payable
        validatePublicStatus(_quantity)
        underMaxSupply(_quantity)
    {
        _mint(msg.sender, _quantity, "", false);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI = _baseURI();
        return bytes(baseURI).length != 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json")) : '';
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function holderAirdrop(address[] calldata boardAddresses, uint256 _quantity) external onlyOwner {

        for (uint i = 0; i < boardAddresses.length; i++) {
            _safeMint(boardAddresses[i], _quantity);
        }
    }   

    function teamClaim() external onlyOwner {
        require(!claimed, "Team already claimed");
        // claim
        _safeMint(teamAddress, claimAmount);
        claimed = true;
    }

    function setFreeMintCount(uint256 _count) external onlyOwner {
        freeMintCount = _count;
    }

    function setMaxPerTxn(uint256 _num) external onlyOwner {
        require(_num >= 0, "Num must be greater than zero");
        maxPerTxn = _num;
    } 

    function setMaxPerWallet(uint256 _num) external onlyOwner {
        require(_num >= 0, "Num must be greater than zero");
        maxPerWallet = _num;
    } 

    function setTokenPrice(uint256 newPrice) external onlyOwner {
        require(newPrice >= 0, "Token price must be greater than zero");
        token_price = newPrice;
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function withdrawFunds() external onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function withdrawFundsToAddress(address _address, uint256 amount) external onlyOwner {
        (bool success, ) =_address.call{value: amount}("");
        require(success, "Transfer failed.");
    }
    
    function flipFreeMint() external onlyOwner {
        freeMintActive = !freeMintActive;
    }

    function flipPublicSale() external onlyOwner {
        publicSaleActive = !publicSaleActive;
    }

}
