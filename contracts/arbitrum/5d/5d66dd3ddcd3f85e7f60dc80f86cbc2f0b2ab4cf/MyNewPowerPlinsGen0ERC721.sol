// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./ReentrancyGuard.sol";
import "./StringsUpgradeable.sol";
import { IERC2981, IERC165 } from "./IERC2981.sol";

contract MyNewPowerPlinsGen0ERC721 is ERC721A, Ownable, ReentrancyGuard, IERC2981 {

    //using Strings for uint256;
    using StringsUpgradeable for uint256;

    bytes32 public merkleRoot;
    mapping(address => uint) public whitelistClaimed;

    uint public maxWhitelistMintPerUser = 3;
    uint public maxMintAmountPerUser = 100;

    string public uriPrefix = '';
    string public uriSuffix = '.json';
    string public hiddenMetadataUri;

    uint256 public cost;
    uint256 public presaleCost;

    uint256 public maxSupply;

    bool public paused = false;
    bool public whitelistMintEnabled = true;
    bool public revealed = false;

    address public beneficiary;
    uint adminDefaultMint = 90;

    struct RoyaltyInfo{
        address receiver;
        uint96 royaltyFees;
    }
    RoyaltyInfo private royaltyInfos = RoyaltyInfo(_msgSender(), 10);

    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _presaleCost,
        uint256 _cost,
        uint256 _maxSupply,
        string memory _hiddenMetadataUri,
        bytes32 _merkleRoot
    ) ERC721A(_tokenName, _tokenSymbol) {
        setPresaleCost(_presaleCost);
        setCost(_cost);
        maxSupply = _maxSupply;
        setHiddenMetadataUri(_hiddenMetadataUri);
        beneficiary = _msgSender();
        ownerMint(_msgSender(),adminDefaultMint);
        merkleRoot = _merkleRoot;
    }

    function mint(uint256 _mintAmount, bytes32[] calldata _merkleProof) external payable nonReentrant{
        require(!paused, 'The contract is paused!');
        uint256 supply = totalSupply();
        require(_mintAmount > 0);
        require(supply + _mintAmount <= maxSupply);
        if(whitelistMintEnabled){
            bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
            require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), 'Invalid proof!');
            require(msg.value >= presaleCost * _mintAmount,"Insufficient funds");
            require(maxWhitelistMintPerUser >= (whitelistClaimed[_msgSender()] + _mintAmount), 'Insufficient mints left');
            whitelistClaimed[_msgSender()] = whitelistClaimed[_msgSender()] + _mintAmount;
            _safeMint(_msgSender(), _mintAmount);
        }
        else{
            require(msg.value >= cost * _mintAmount,"Insufficient funds");
            _safeMint(_msgSender(), _mintAmount);
        }
    }

    function ownerMint(address to, uint256 amount) public onlyOwner {
        _internalMint(to, amount);
    }

    function _internalMint(address _to, uint256 _mintAmount) private {
        uint256 supply = totalSupply();
        require(supply + _mintAmount <= maxSupply);
        _safeMint(_to, _mintAmount);
    }
    function setMaxWhitelistMintPerUser(uint _maxAmount) external  onlyOwner{
        maxWhitelistMintPerUser = _maxAmount;
    }

    function setMaxMintAmountPerUser(uint256 _maxMintAmountPerUser) external  onlyOwner {
        maxMintAmountPerUser = _maxMintAmountPerUser;
    }

    function setCost(uint256 _cost) public  onlyOwner {
        cost = _cost;
    }

    function setPresaleCost(uint256 _cost) public  onlyOwner {
        presaleCost = _cost;
    }

    function walletOfOwner(address _owner) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
        uint256 currentTokenId = _startTokenId();
        uint256 ownedTokenIndex = 0;
        address latestOwnerAddress;

        while (ownedTokenIndex < ownerTokenCount && currentTokenId < _currentIndex) {
            TokenOwnership memory ownership = _ownerships[currentTokenId];
            if (!ownership.burned) {
                if (ownership.addr != address(0)) {
                    latestOwnerAddress = ownership.addr;
                }

                if (latestOwnerAddress == _owner) {
                    ownedTokenIds[ownedTokenIndex] = currentTokenId;

                    ownedTokenIndex++;
                }
            }

            currentTokenId++;
        }

        return ownedTokenIds;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function tokenURI(uint256 _tokenId) public view  override returns (string memory) {
        require(_exists(_tokenId), 'ERC721Metadata: URI query for nonexistent token');
        if (revealed == false) {
            return hiddenMetadataUri;
        }
        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix))
        : '';
    }

    function setRevealed(bool _state) external  onlyOwner {
        revealed = _state;
    }

    function setHiddenMetadataUri(string memory _hiddenMetadataUri) public  onlyOwner {
        hiddenMetadataUri = _hiddenMetadataUri;
    }

    function setUriPrefix(string memory _uriPrefix) external  onlyOwner {
        uriPrefix = _uriPrefix;
    }

    function setUriSuffix(string memory _uriSuffix) external  onlyOwner {
        uriSuffix = _uriSuffix;
    }


    function setPaused(bool _state) external  onlyOwner {
        paused = _state;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external  onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setWhitelistMintEnabled(bool _state) external  onlyOwner {
        whitelistMintEnabled = _state;
    }

    function setBeneficiary(address _beneficiary) external onlyOwner {
        beneficiary = _beneficiary;
    }

    function setRoyaltyInfo(address _receiver, uint96 _royaltyFees) external onlyOwner {
        require(_receiver != address(0), "Invalid parameters");
        royaltyInfos.receiver = _receiver;
        royaltyInfos.royaltyFees = _royaltyFees;
    }

    function withdraw() public onlyOwner {
        payable(beneficiary).transfer(address(this).balance);
    }

    function getTotalSupply() external view returns(uint supply){
        return totalSupply();
    }

    function _baseURI() internal view  override returns (string memory) {
        return uriPrefix;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721A, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view returns (address, uint256) {
        _tokenId;
        uint256 royaltyAmount = (_salePrice * royaltyInfos.royaltyFees) / 100;
        return (royaltyInfos.receiver, royaltyAmount);
    }
}

