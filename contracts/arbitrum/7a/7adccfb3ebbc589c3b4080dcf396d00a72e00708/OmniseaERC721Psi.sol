// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./IOmniseaERC721Psi.sol";
import "./IOmniseaONFT721.sol";
import "./IOmniseaDropsScheduler.sol";
import "./IERC2981Royalties.sol";
import {CreateParams, Phase, BasicCollectionParams} from "./ERC721Structs.sol";
import "./Strings.sol";
import "./ERC721Psi.sol";
import "./ERC721PsiAddressData.sol";
import "./ReentrancyGuard.sol";
import "./IOmniseaUniversalONFT721.sol";

contract OmniseaERC721Psi is IOmniseaERC721Psi, IOmniseaONFT721, ERC721PsiAddressData, ReentrancyGuard {
    using Strings for uint256;

    event BatchMinted(address to, uint256 nextTokenId, uint256 quantity);

    modifier onlyOwner() {
        require(owner == msg.sender);
        _;
    }

    IOmniseaUniversalONFT721 public universalONFT;
    IOmniseaDropsScheduler public scheduler;
    address internal immutable _revenueManager = address(0x61104fBe07ecc735D8d84422c7f045f8d29DBf15);
    uint24 public maxSupply;
    string public collectionURI;
    address public override dropsManager;
    bool public isZeroIndexed;
    string public tokensURI;
    uint256 public endTime;
    uint24 public royaltyAmount;
    address public override owner;
    bool private isInitialized;
    bool private isMintedToPlatform;

    function initialize(
        CreateParams memory params,
        address _owner,
        address _dropsManager,
        address _scheduler,
        address _universalONFT
    ) external {
        require(!isInitialized);
        _init(params.name, params.symbol);
        isInitialized = true;
        dropsManager = _dropsManager;
        tokensURI = params.tokensURI;
        maxSupply = params.maxSupply;
        collectionURI = params.uri;
        isZeroIndexed = params.isZeroIndexed;
        endTime = params.endTime;
        _setNextTokenId(isZeroIndexed ? 0 : 1);
        royaltyAmount = params.royaltyAmount;
        owner = _owner;
        scheduler = IOmniseaDropsScheduler(_scheduler);
        universalONFT = IOmniseaUniversalONFT721(_universalONFT);
    }

    function contractURI() public view returns (string memory) {
        return string(abi.encodePacked("ipfs://", collectionURI));
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        if (maxSupply == 0 || bytes(tokensURI).length == 0) {
            return contractURI();
        }

        return string(abi.encodePacked("ipfs://", tokensURI, "/", tokenId.toString(), ".json"));
    }

    function mint(address _minter, uint24 _quantity, bytes32[] memory _merkleProof, uint8 _phaseId) external override nonReentrant {
        require(msg.sender == dropsManager);
        require(isAllowed(_minter, _quantity, _merkleProof, _phaseId), "!isAllowed");
        scheduler.increasePhaseMintedCount(_minter, _phaseId, _quantity);
        _mint(_minter, _quantity);
        emit BatchMinted(_minter, _nextTokenId(), _quantity);
    }

    function mintPrice(uint8 _phaseId) public view override returns (uint256) {
        return scheduler.mintPrice(_phaseId);
    }

    function isAllowed(address _account, uint24 _quantity, bytes32[] memory _merkleProof, uint8 _phaseId) internal view returns (bool) {
        require(block.timestamp < endTime);
        uint256 _newTotalMinted = totalMinted() + _quantity;
        if (maxSupply > 0) require(maxSupply >= _newTotalMinted);

        return scheduler.isAllowed(_account, _quantity, _merkleProof, _phaseId);
    }

    function setPhase(
        uint8 _phaseId,
        uint256 _from,
        uint256 _to,
        bytes32 _merkleRoot,
        uint24 _maxPerAddress,
        uint256 _price
    ) external onlyOwner {
        scheduler.setPhase(_phaseId, _from, _to, _merkleRoot, _maxPerAddress, _price);
    }

    function setTokensURI(string memory _uri) external onlyOwner {
        require(block.timestamp < endTime);
        tokensURI = _uri;
    }

    function preMintToTeam(uint256 _quantity) external nonReentrant onlyOwner {
        if (maxSupply > 0) {
            require(maxSupply >= totalMinted() + _quantity);
        } else {
            require(block.timestamp < endTime);
        }
        _mint(owner, _quantity);
    }

    function preMintToPlatform(uint256 _quantity) external {
        require(msg.sender == _revenueManager && !isMintedToPlatform && _quantity <= 5);
        if (maxSupply > 0) {
            require(maxSupply >= totalMinted() + _quantity);
        } else {
            require(block.timestamp < endTime);
        }
        isMintedToPlatform = true;
        _mint(_revenueManager, _quantity);
    }

    function _startTokenId() internal view override returns (uint256) {
        return isZeroIndexed ? 0 : 1;
    }

    function royaltyInfo(uint256, uint256 value) external view returns (address _receiver, uint256 _royaltyAmount) {
        _receiver = owner;
        _royaltyAmount = (value * royaltyAmount) / 10000;
    }

    function setRoyaltyAmount(uint24 _royaltyAmount) external onlyOwner {
        royaltyAmount = _royaltyAmount;
    }

    function sendFrom(address _from, uint16 _dstChainId, bytes calldata _toAddress, uint _tokenId, address payable _refundAddress, address _zroPaymentAddress, bytes calldata _adapterParams) external override payable {
        universalONFT.sendFrom{value: msg.value}(_from, _dstChainId, _toAddress, _tokenId, _refundAddress, _zroPaymentAddress, _adapterParams, _getBasicCollectionParams());
    }

    function estimateSendFee(uint16 _dstChainId, bytes calldata _toAddress, uint _tokenId, bool _useZro, bytes calldata _adapterParams) external override view returns (uint nativeFee, uint zroFee) {
        return universalONFT.estimateSendFee(_dstChainId, _toAddress, _tokenId, _useZro, _adapterParams, _getBasicCollectionParams());
    }

    function sendBatchFrom(address _from, uint16 _dstChainId, bytes calldata _toAddress, uint[] calldata _tokenIds, address payable _refundAddress, address _zroPaymentAddress, bytes calldata _adapterParams) external override payable {
        universalONFT.sendBatchFrom{value: msg.value}(_from, _dstChainId, _toAddress, _tokenIds, _refundAddress, _zroPaymentAddress, _adapterParams, _getBasicCollectionParams());
    }

    function estimateSendBatchFee(uint16 _dstChainId, bytes calldata _toAddress, uint[] calldata _tokenIds, bool _useZro, bytes calldata _adapterParams) external override view returns (uint nativeFee, uint zroFee) {
        return universalONFT.estimateSendBatchFee(_dstChainId, _toAddress, _tokenIds, _useZro, _adapterParams, _getBasicCollectionParams());
    }

    function exists(uint256 tokenId) public view virtual override returns (bool) {
        return _exists(tokenId);
    }

    function _getBasicCollectionParams() internal view returns (BasicCollectionParams memory) {
        return BasicCollectionParams(name(), symbol(), collectionURI, tokensURI, maxSupply, owner);
    }
}

