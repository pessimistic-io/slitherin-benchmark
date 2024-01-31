// SPDX-License-Identifier: MIT

/*

                              @@      @@@@@                                                    @@@@@@@@@@                                                       
                           @@@((@@@@@@(((((@@@                                           @@@@@@((((((((@@   @@@@@@@@                                            
                @@@@@@@@@@@(((##((((((#####(((@@                                         @@@%%%%%%%%%%%((@@@%%%(((((@@@                                         
                @@@(((########################@@                                       @@%%%%%%%%%%%%%%@@%%%%%%%%(((@@@                                         
                   @@@((###@@@@@@@@@@@@@@@@@@@@@@@@                                    @@@@@@@@@@@@@@@@@@@@@@@@%%%%%@@@                                         
              @@@@@@@@((###@@@(((((((((((((((((((((@@@                              @@@((###########%%%%%%%%%%%@@%%%@@@                                         
           @@@((((((((##@@@((((((((///////////////////@@                         @@@(((################%%%%%%%%%%@@@(((@@                                       
           @@@((######@@((((((((//////////////////////@@                         @@@@@@@@@@@@@@@@###########%%%%%@@@%%%((@@@                                    
              @@(((###@@((((((////////////////////////@@                       @@...             @@@###########%%@@@%%%%%@@@                                    
           @@@  @@@###@@((((((//@@@@@@@@//////////////@@@@@@@@              @@@..      @@@@@        @@@########%%@@@%%%%%@@@                                    
        @@@(((@@(((###@@((((((@@...     @@@////////@@@..      @@            @@@..      @@@@@        @@@########%%@@@%%%@@                                       
        @@@(((((######@@(((@@@..   @@@     @@@//@@@...  @@@     @@@         @@@..      @@@@@        @@@########%%@@@(((@@                                       
        @@@(((((######@@(((@@@..   @@@     @@@//@@@...  @@@     @@@         @@@..      @@@@@        @@@########%%@@@(((@@                                       
           @@@((######@@(((@@@..   @@@     @@@//@@@...  @@@     @@@            @@...             @@@###########%%@@@(((@@                                       
              @@(((###@@((((((@@...     @@@////////@@@..      @@            @@@##@@@@@@@@@@@@@@@@##############%%@@@(((@@                                       
              @@(((###@@((((((//@@@@@@@@//////////////@@@@@@@@              @@@################################%%@@@%%%((@@@                                    
           @@@(((((###@@((((((////////////////////////@@                 @@@(((#####@@@#####@@@################%%@@@%%%%%(((@@@                                 
           @@@((######@@((((((/////@@@/////////////@@@@@                 @@@(((#####@@@#####@@@################%%@@@%%%%%(((@@@                                 
              @@(((###@@((((((//@@@%%%@@@@@@@@@@@@@%%%@@                 @@@(((################################%%@@@%%%%%@@@                                    
                @@@(((@@((((((//@@@%%%  %%%%%%%%   %%%@@                 @@@(((################################%%@@@%%%%%@@@                                    
              @@(((###@@((((((/////@@@%%%%%%%%%%%%%@@@@@                 @@@(((################################%%@@@%%%@@                                       
              @@(((###@@((((((////////@@@@@@@@@@@@@///@@                    @@@((##############################%%@@@@@@                                         
                @@@(((@@((((((/////////////////////@@@                         @@((((((#####################@@@%%@@@(((@@                                       
                   @@@@@((((((/////@@@@@@@@@@@@@@@@                              @@@@@@@@@@@@@@@@@@@@@@@@@@@%%%%%@@@%%%((@@@                                    
                      @@((((((/////@@@                                                              @@@%%%%%%%%%%@@@%%%%%@@@                                    
                      @@((((((((///@@@                                                              @@@%%%%%%%%%%@@@%%%@@                                       
                      @@(((((((((((@@@                                                              @@@%%%%%%%%%%@@@@@@                                         

*/

/// @title NormalDay

pragma solidity >=0.8.9 <0.9.0;

import "./ERC721AQueryable.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./ReentrancyGuard.sol";
import "./Strings.sol";

contract NormalDay is ERC721AQueryable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    bytes32 public merkleRoot;

    string public uriPrefix = "";
    string public uriSuffix = ".json";
    string public hiddenMetadataUri;
    string public provenance;

    uint256 public cost;
    uint256 public maxSupply;
    uint256 public maxPerTx;
    uint256 public maxPerWallet;

    uint256 public wlCost;
    uint256 public wlMaxSupply;
    uint256 public wlMaxPerTx;
    uint256 public wlMaxPerWallet;
    uint256 public wlMaxFreePerWallet;

    bool public publicEnabled = false;
    bool public whitelistMintEnabled = false;
    bool public revealed = false;

    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _cost,
        uint256 _maxSupply,
        uint256 _maxPerTx,
        uint256 _maxPerWallet,
        uint256 _wlCost,
        uint256 _wlMaxSupply,
        uint256 _wlMaxPerWallet,
        uint256 _wlMaxFreePerWallet,
        string memory _hiddenMetadataUri
    ) ERC721A(_tokenName, _tokenSymbol) {
        setCost(_cost, _wlCost);
        maxSupply = _maxSupply;
        wlMaxSupply = _wlMaxSupply;
        setMaxPerTx(_maxPerTx, _maxPerTx);
        setMaxPerWallet(_maxPerWallet, _wlMaxPerWallet, _wlMaxFreePerWallet);
        setHiddenMetadataUri(_hiddenMetadataUri);
    }

    modifier mintCompliance(uint256 _mintAmount) {
        require(
            _mintAmount > 0 && _mintAmount <= maxPerTx,
            "Invalid mint amount!"
        );
        require(
            _numberMinted(_msgSender()) + _mintAmount - uint256(_getAux(_msgSender())) <= maxPerWallet,
            "Max per wallet exceeded!"
        );
        require(
            totalSupply() + _mintAmount <= maxSupply,
            "Max supply exceeded!"
        );
        _;
    }

    modifier mintPriceCompliance(uint256 _mintAmount) {
        require(msg.value >= cost * _mintAmount, "Insufficient funds!");
        _;
    }

    modifier whitelistMintCompliance(uint256 _mintAmount) {
        require(
            _mintAmount > 0 && _mintAmount <= wlMaxPerTx,
            "Invalid mint amount!"
        );
        require(
            uint256(_getAux(_msgSender())) + _mintAmount <= wlMaxPerWallet,
            "Already minted max WL per wallet!"
        );
        require(
            totalSupply() + _mintAmount <= wlMaxSupply,
            "WL Max supply exceeded!"
        );
        _;
    }

    modifier whitelistMintPriceCompliance(uint256 _mintAmount) {        
        if (uint256(_getAux(_msgSender())) < wlMaxFreePerWallet) {
            uint256 freeRemaining = wlMaxFreePerWallet - uint256(_getAux(_msgSender()));

            if (freeRemaining < _mintAmount) {
                uint256 toPay = _mintAmount - freeRemaining;

                require(msg.value >= wlCost * toPay, "Insufficient funds!");
            }

        } else {
            require(msg.value >= wlCost * _mintAmount, "Insufficient funds!");
        }        
        _;
    }

    function whitelistMint(uint256 _mintAmount, bytes32[] calldata _merkleProof)
        public
        payable
        whitelistMintCompliance(_mintAmount)
        whitelistMintPriceCompliance(_mintAmount)
    {
        // Verify whitelist requirements
        require(whitelistMintEnabled, "Whitelist sale is not open!");
        require(!publicEnabled, "Public sale is already open!");
        bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, leaf),
            "Invalid proof!"
        );
                
        _safeMint(_msgSender(), _mintAmount);
        _setAux(_msgSender(), _getAux(_msgSender()) + uint64(_mintAmount));
    }

    function mint(uint256 _mintAmount)
        public
        payable
        mintCompliance(_mintAmount)
        mintPriceCompliance(_mintAmount)
    {
        require(publicEnabled, "Public sale is not open!");

        _safeMint(_msgSender(), _mintAmount);
    }

    function mintForAddress(uint256 _mintAmount, address _receiver)
        public
        mintCompliance(_mintAmount)
        onlyOwner
    {
        _safeMint(_receiver, _mintAmount);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (revealed == false) {
            return hiddenMetadataUri;
        }

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        _tokenId.toString(),
                        uriSuffix
                    )
                )
                : "";
    }

    function setRevealed(bool _state) public onlyOwner {
        revealed = _state;
    }

    function setCost(uint256 _cost, uint256 _wlCost) public onlyOwner {
        cost = _cost;
        wlCost = _wlCost;
    }

    function setMaxPerTx(uint256 _maxPerTx, uint256 _wlMaxPerTx)
        public
        onlyOwner
    {
        maxPerTx = _maxPerTx;
        wlMaxPerTx = _wlMaxPerTx;
    }

    function setMaxPerWallet(uint256 _maxPerWallet, uint256 _wlMaxPerWallet, uint256 _wlMaxFreePerWallet)
        public
        onlyOwner
    {
        maxPerWallet = _maxPerWallet;
        wlMaxPerWallet = _wlMaxPerWallet;
        wlMaxFreePerWallet = _wlMaxFreePerWallet;
    }


    function setHiddenMetadataUri(string memory _hiddenMetadataUri)
        public
        onlyOwner
    {
        hiddenMetadataUri = _hiddenMetadataUri;
    }

    function setUriPrefix(string memory _uriPrefix) public onlyOwner {
        uriPrefix = _uriPrefix;
    }

    function setUriSuffix(string memory _uriSuffix) public onlyOwner {
        uriSuffix = _uriSuffix;
    }

    function setPublicEnabled(bool _state) public onlyOwner {
        publicEnabled = _state;
    }

    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setWhitelistMintEnabled(bool _state) public onlyOwner {
        whitelistMintEnabled = _state;
    }

    function setProvenance(string memory _provenance) public onlyOwner {
        provenance = _provenance;
    }

    function reserve(uint256 quantity) public payable onlyOwner {
        require(
            totalSupply() + quantity <= maxSupply,
            "Not enough tokens left"
        );
        _safeMint(msg.sender, quantity);
    }

    function withdraw() public onlyOwner nonReentrant {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return uriPrefix;
    }
}
