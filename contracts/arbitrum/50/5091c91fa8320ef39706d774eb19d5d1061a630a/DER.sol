// SPDX-License-Identifier: MIT

pragma solidity 0.8.8;

import "./Ownable.sol";
import "./ERC721A.sol";
                                                                                                

contract DER is ERC721A, Ownable {
    enum Status {
        Pending,
        Sale,
        Finished
    }

    Status public status;
    bytes32 public root;
    uint256 public tokensReserved;
    uint256 public PRICE;
    uint256 public price_whitelist = 0.028 ether;
    uint256 public price_public = 0.035 ether;
    uint96 public royaltyNumerator;
    uint256 public immutable maxMint;
    uint256 public immutable maxSupply;
    uint256 public immutable reserveAmount;
    mapping(address => bool) public whitelist;

    event Minted(address minter, uint256 amount);
    event StatusChanged(Status status);
    event RootChanged(bytes32 root);
    event ReservedToken(address minter, address recipient, uint256 amount);
    event BaseURIChanged(string newBaseURI);
    event AddressAdded(address indexed addr);

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "Contract is not allowed to mint.");
        _;
    }

    constructor(
        string memory initBaseURI,
        uint256 _maxMint,
        uint256 _maxSupply,
        uint256 _reserveAmount
    )
        ERC721A(
            "Mutant DER Club",
            "DER",
            _reserveAmount,
            _maxSupply
        )
    {
        baseURI = initBaseURI;
        maxMint = _maxMint;
        maxSupply = _maxSupply;
        reserveAmount = _reserveAmount;
    }

    function addToWhitelist(address[] memory addresses) external {
        for (uint256 i = 0; i < addresses.length; i++) {
            address addr = addresses[i];
            whitelist[addr] = true;
            emit AddressAdded(addr);
        }
    }

    function reserve(address recipient, uint256 amount) external onlyOwner {
        require(recipient != address(0), "Zero address");
        require(amount > 0, "Invalid amount");
        require(
            totalSupply() + amount <= collectionSize,
            "Max supply exceeded"
        );
        require(
            tokensReserved + amount <= reserveAmount,
            "Max reserve amount exceeded"
        );

        uint256 multiple = amount / maxBatchSize;
        for (uint256 i = 0; i < multiple; i++) {
            _safeMint(recipient, maxBatchSize);
        }
        uint256 remainder = amount % maxBatchSize;
        if (remainder != 0) {
            _safeMint(recipient, remainder);
        }
        tokensReserved += amount;
        emit ReservedToken(msg.sender, recipient, amount);
    }

    function mint(uint256 amount) external payable callerIsUser {
        require(status == Status.Sale, "Public sale is not active.");
        require(numberMinted(msg.sender) + amount <= maxMint, "Max mint amount per tx exceeded.");
        require(
            totalSupply() + amount + reserveAmount - tokensReserved <=
                collectionSize,
            "Max supply exceeded."
        );
        if(whitelist[msg.sender] == true){
            PRICE = 0.028 ether;
        }
        else{
            PRICE = 0.035 ether;
        }
        _safeMint(msg.sender, amount);
        refundIfOver(PRICE * amount);
        emit Minted(msg.sender, amount);
    }

    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "Need to send more ETH.");
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    function withdraw() external onlyOwner {
        require(status == Status.Finished, "Invalid status for withdrawn.");

        payable(owner()).transfer(address(this).balance);
    }

    /**
    * @dev For each existing tokenId, it returns the URI where metadata is stored
    * @param tokenId Token id
    */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        string memory uri = super.tokenURI(tokenId);
        return bytes(uri).length > 0 ? string(abi.encodePacked(uri, ".json")) : "";
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    function setStatus(Status _status) external onlyOwner {
        status = _status;
        emit StatusChanged(_status);
    }

    function setOwnersExplicit(uint256 quantity) external onlyOwner {
        _setOwnersExplicit(quantity);
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function getOwnershipData(uint256 tokenId)
        external
        view
        returns (TokenOwnership memory)
    {
        return ownershipOf(tokenId);
    }

    function checkPriceByWallet() public view returns(uint256) {
        if(whitelist[msg.sender] == true){
            return price_whitelist;
        }
        else{
            return price_public;
        }
    }



    //// CODE for Royalties
    
    /**
     * @dev Sets the royalty information that all ids in this contract will default to.
     *
     * Requirements:
     *
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        require(feeNumerator <= 10000, "ERC2981: royalty fee exceeds 10% threshold");
        require(receiver != address(0), "ERC2981: invalid receiver");
        royaltyNumerator = feeNumerator;
        _defaultRoyaltyInfo = RoyaltyInfo(receiver, feeNumerator);
    }

    /**
     * @dev Removes default royalty information.
     */
    function deleteDefaultRoyalty() external onlyOwner {
        delete _defaultRoyaltyInfo;
    }

    /**
     * @dev Sets the royalty information for a specific token id, overriding the global default.
     *
     * Requirements:
     *
     * - `tokenId` must be already minted.
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        require(feeNumerator <= 15000, "ERC2981: royalty fee exceeds the 15% threshold");
        require(receiver != address(0), "ERC2981: invalid parameters");

        _tokenRoyaltyInfo[tokenId] = RoyaltyInfo(receiver, feeNumerator);
    }

    /**
     * @dev Resets royalty information for the token id back to the global default.
     */
    function resetTokenRoyalty(uint256 tokenId) external onlyOwner {
        delete _tokenRoyaltyInfo[tokenId];
    }
}
