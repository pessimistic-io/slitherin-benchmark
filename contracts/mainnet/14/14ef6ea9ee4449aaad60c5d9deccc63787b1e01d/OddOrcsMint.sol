//SPDX-License-Identifier: None
pragma solidity ^0.8.13;

import "./IERC721.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ERC721AUpgradeable.sol";
import "./OddOrcsWhitelist.sol";
import "./RevokableOperatorFiltererUpgradeable.sol";
import "./RevokableDefaultOperatorFiltererUpgradeable.sol";
import "./UpdatableOperatorFilterer.sol";

contract OddOrcsMint is
    ERC721AUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    Whitelist,
    ReentrancyGuardUpgradeable,
    RevokableDefaultOperatorFiltererUpgradeable
{
    struct list {
        uint256 startTime;
        uint256 endTime;
        uint256 limit;
        uint256 remainingTokens;
        uint256 mintPrice;
    }

    IERC721 spectrumNFT;
    string public baseURI;
    address public designatedSigner;

    uint256 public maxSupply;
    uint256 public ownerRemainingTokens;

    address public treasury;

    list public spectrumPassHoldersSale;
    list public whitelistSale;
    list public publicSale;

    mapping(uint256 => uint256) public spectrumPassHoldersSaleTracker;
    mapping(address => uint256) public whitelistSaleTracker;
    mapping(address => uint256) public publicSaleTracker;

    modifier checkSupply(uint256 _amount) {
        require(_amount > 0, "Invalid Amount");
        require(_amount + totalSupply() <= maxSupply - ownerRemainingTokens, "Exceeding Max Supply");
        _;
    }

    /**
    @notice This function is used to initialize values of contracts  
    @param _name Collection name  
    @param _symbol Collection Symbol  
    @param _designatedSigner Whitelist signer address of presale buyers  
    */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _designatedSigner,
        address _spectrumNFT,
        address _treasury
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC721A_init(_name, _symbol);
        __OddOrcsSigner_init();

        treasury = _treasury;

        spectrumNFT = IERC721(_spectrumNFT);
        designatedSigner = _designatedSigner;
        maxSupply = 5555;
        ownerRemainingTokens = 1;

        spectrumPassHoldersSale.startTime = 1674020800;
        spectrumPassHoldersSale.endTime = spectrumPassHoldersSale.startTime + 8 hours;
        spectrumPassHoldersSale.limit = 1;
        spectrumPassHoldersSale.remainingTokens = 1000;
        spectrumPassHoldersSale.mintPrice = 0 ether;

        whitelistSale.startTime = 1674020800;
        whitelistSale.endTime = whitelistSale.startTime + 8 hours;
        whitelistSale.limit = 2;
        whitelistSale.remainingTokens = 1700;
        whitelistSale.mintPrice = 0.005 ether;

        publicSale.startTime = 1674020800;
        publicSale.endTime = publicSale.startTime + 8 hours;
        publicSale.limit = 2;
        publicSale.remainingTokens = 4555;
        publicSale.mintPrice = 0.008 ether;
    }

    /**
    @notice This function allows owner to airdrop tokens
    @param _amount amount of tokens to mint in one transaction  
    */
    function airdrop(uint256 _amount) external onlyOwner {
        require(_amount + totalSupply() <= maxSupply, "Exceeding Supply");
        require(_amount <= ownerRemainingTokens, "Exceeding Airdrop Allotment");

        ownerRemainingTokens -= _amount;
        _mint(msg.sender, _amount);
    }

    /**
    @notice This function allows Spectrum Pass Holders to mint   
    @param _tokenIds Spectrum Pass Ids held by the caller  
    @param _amounts No. of tokens the caller wishes to mint against the tokenIds   
    */
    function spectrumMint(uint256[] memory _tokenIds, uint256[] memory _amounts) external whenNotPaused nonReentrant {
        uint256 totalAmountToMint = 0;
        require(
            block.timestamp > spectrumPassHoldersSale.startTime && block.timestamp <= spectrumPassHoldersSale.endTime,
            "Spectrum: Not active"
        );
        require(_tokenIds.length == _amounts.length, "Spectrum: Invalid Input");

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            require(_tokenIds[i] != 0 && _amounts[i] != 0, "Spectrum: Null Input");
            require(spectrumNFT.ownerOf(_tokenIds[i]) == msg.sender, "Spectrum: !Owner");
            require(
                _amounts[i] + spectrumPassHoldersSaleTracker[_tokenIds[i]] <= spectrumPassHoldersSale.limit,
                "Spectrum: Claimed Already"
            );
            totalAmountToMint += _amounts[i];
            spectrumPassHoldersSaleTracker[_tokenIds[i]] += _amounts[i];
        }
        require(totalAmountToMint <= spectrumPassHoldersSale.remainingTokens, "Spectrum: Not Enough Remaining");
        require(totalAmountToMint + totalSupply() <= maxSupply - ownerRemainingTokens, "Exceeding Max Supply");

        spectrumPassHoldersSale.remainingTokens -= totalAmountToMint;

        _mint(msg.sender, totalAmountToMint);
    }

    /**
    @notice This function allows whitelisted addresses to mint
    @param _whitelist Whitelist object which contains user address signed by a designated private key  
    @param _amount Amount of tokens to mint
    */
    function whitelistSaleMint(
        whitelist memory _whitelist,
        uint256 _amount
    ) external payable whenNotPaused nonReentrant checkSupply(_amount) {
        require(getSigner(_whitelist) == designatedSigner, "!Signer");
        require(_whitelist.userAddress == msg.sender, "!Sender");
        require(_whitelist.listType == 1, "!List");
        require(
            block.timestamp > whitelistSale.startTime && block.timestamp <= whitelistSale.endTime,
            "WhitelistSale: Not active"
        );
        require(
            _amount + whitelistSaleTracker[_whitelist.userAddress] <= whitelistSale.limit,
            "WhitelistSale: Exceeding Individual Quota"
        );
        require(msg.value == whitelistSale.mintPrice * _amount, "WhitelistSale: Not Enough Funds paid");
        require(_amount <= whitelistSale.remainingTokens, "WhitelistSale: Sold Out");

        whitelistSaleTracker[_whitelist.userAddress] += _amount;
        whitelistSale.remainingTokens -= _amount;

        _mint(_whitelist.userAddress, _amount);
    }

    /**
    @notice This function allows anyone to mint    
    @param _amount Amount of tokens to mint   
    */
    function publicMint(uint256 _amount) external payable whenNotPaused nonReentrant checkSupply(_amount) {
        require(msg.sender == tx.origin, "PublicSale: Only wallets allowed");
        require(
            block.timestamp >= publicSale.startTime && block.timestamp <= publicSale.endTime,
            "PublicSale: Not Active"
        );
        require(msg.value == publicSale.mintPrice * _amount, "PublicSale: Not Enough Funds paid");
        require(publicSaleTracker[msg.sender] + _amount <= publicSale.limit, "PublicSale: Exceeding Individual Quota");

        publicSaleTracker[msg.sender] += _amount;
        publicSale.remainingTokens -= _amount;

        _mint(msg.sender, _amount);
    }

    /**
    @notice The function allows owner to pause/ unpause mint  
    */
    function togglePause() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    ////////////////
    ////Setters////
    //////////////

    function setBaseURI(string memory baseURI_) public onlyOwner {
        require(bytes(baseURI_).length > 0, "Invalid Base URI Provided");
        baseURI = baseURI_;
    }

    function setDesignatedSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "Invalid Address Provided");
        designatedSigner = _signer;
    }

    function setMaxSupply(uint256 _supply) external onlyOwner {
        require(totalSupply() < _supply, "Total Supply Exceeding");
        maxSupply = _supply;
    }

    function setOwnerCap(uint256 _cap) external onlyOwner {
        ownerRemainingTokens = _cap;
    }

    function setSpectrumNFTAddress(address _spectrumNFT) external onlyOwner {
        spectrumNFT = IERC721(_spectrumNFT);
    }

    function setTreasuryAddress(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setSpectrumPassHoldersSaleConditions(list calldata _spectrumPassHoldersSale) external onlyOwner {
        spectrumPassHoldersSale.startTime = _spectrumPassHoldersSale.startTime;
        spectrumPassHoldersSale.endTime = _spectrumPassHoldersSale.endTime;
        spectrumPassHoldersSale.limit = _spectrumPassHoldersSale.limit;
        spectrumPassHoldersSale.remainingTokens = _spectrumPassHoldersSale.remainingTokens;
        spectrumPassHoldersSale.mintPrice = _spectrumPassHoldersSale.mintPrice;
    }

    function setWhitelistSaleConditions(list calldata _whitelistSale) external onlyOwner {
        whitelistSale.startTime = _whitelistSale.startTime;
        whitelistSale.endTime = _whitelistSale.endTime;
        whitelistSale.limit = _whitelistSale.limit;
        whitelistSale.remainingTokens = _whitelistSale.remainingTokens;
        whitelistSale.mintPrice = _whitelistSale.mintPrice;
    }

    function setPublicSaleConditions(list calldata _publicSale) external onlyOwner {
        publicSale.startTime = _publicSale.startTime;
        publicSale.endTime = _publicSale.endTime;
        publicSale.limit = _publicSale.limit;
        publicSale.remainingTokens = _publicSale.remainingTokens;
        publicSale.mintPrice = _publicSale.mintPrice;
    }

    function withdraw() external onlyOwner {
        payable(treasury).transfer(address(this).balance);
    }

    ////////////////
    ///Overridden///
    ////////////////

    /**
    @notice This function is used to get first token id      
    */
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    /**
    @notice This function is used to get base URI value     
    */
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function getChainID() external view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
    public
    override
    onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function owner()
    public
    view
    virtual
    override (OwnableUpgradeable, RevokableOperatorFiltererUpgradeable)
    returns (address)
    {
        return OwnableUpgradeable.owner();
    }
}

