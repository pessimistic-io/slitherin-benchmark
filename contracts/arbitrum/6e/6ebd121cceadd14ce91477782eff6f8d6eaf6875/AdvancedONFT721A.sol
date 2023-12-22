// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8;

import "./ONFT721A.sol";
import "./Strings.sol";
import "./MerkleProofLib.sol";
import "./IERC20.sol";
error saleNotStarted();
error zeroAmount();
error maxSupplyReached();
error insufficientValue();
error nonWhitelist();

contract AdvancedONFT721A is ONFT721A {

    using Strings for uint;
    using MerkleProofLib for bytes32[];

    struct FinanceDetails {
        
        address payable beneficiary;
        address payable taxRecipient;
        address token;
        uint128 price;
        uint128 wlPrice;
        uint16 tax;
        

    }

    struct Metadata {
        string baseURI;
        string hiddenMetadataURI;
    }

    struct NFTState {
        bool saleStarted;
        bool revealed;
    }

    uint256 public startId;
    uint256 public maxId;
    uint256 public maxGlobalId;
    bytes32 public merkleRoot;

    FinanceDetails public financeDetails;
    Metadata public metadata;
    NFTState public state;

    modifier onlyBenficiaryAndOwner() {
        require(msg.sender == financeDetails.beneficiary || msg.sender == owner(), "Caller is not beneficiary or owner");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        uint256 _startId,
        uint256 _maxId,
        uint256 _maxGlobalId,
        string memory _baseTokenURI,
        string memory _hiddenURI,
        uint16 _tax,
        uint128 _price,
        uint128 _wlPrice,
        address token,
        address _taxRecipient,
        address _beneficiary
    ) ONFT721A(_name, _symbol, 1, _lzEndpoint, _startId) {
        startId = _startId;
        maxGlobalId = _maxGlobalId;
        maxId = _maxId;
        financeDetails = FinanceDetails(payable(_beneficiary), payable(_taxRecipient), token, _price, _wlPrice, _tax);
        metadata = Metadata(_baseTokenURI, _hiddenURI);
    }

    function mint(uint256 _nbTokens) public virtual payable {
        if (!state.saleStarted) _revert(saleNotStarted.selector);
        if (_nbTokens == 0) _revert(zeroAmount.selector);
        if (_nextTokenId() + _nbTokens - 1 > maxId) _revert(maxSupplyReached.selector);
        IERC20(financeDetails.token).transferFrom(msg.sender, address(this), financeDetails.price * _nbTokens);
        _mint(msg.sender, _nbTokens);
    }

    function whitelistMint(uint256 _nbTokens, bytes32[] calldata _merkleProof) public virtual payable {
        if (!state.saleStarted) _revert(saleNotStarted.selector);
        if (!(_merkleProof.verify(merkleRoot, keccak256(abi.encodePacked(msg.sender))))) _revert(nonWhitelist.selector);
        if (_nbTokens == 0) _revert(zeroAmount.selector);
        if (_nextTokenId() + _nbTokens - 1 > maxId) _revert(maxSupplyReached.selector);

        IERC20(financeDetails.token).transferFrom(msg.sender, address(this), financeDetails.wlPrice * _nbTokens);
        _mint(msg.sender, _nbTokens);        
    }

    function _getMaxGlobalId() internal view override returns (uint256) {
        return maxGlobalId;
    }

    function _getMaxId() internal view override returns (uint256) {
        return maxId;
    }

    function _startTokenId() internal view override returns(uint256) {
        return startId;
    }

    function setMerkleRoot(bytes32 _newRoot) public onlyBenficiaryAndOwner() {
        merkleRoot = _newRoot;
    }
    function setMintRange(uint32 _start, uint32 _end) public onlyOwner {
        require (_start > uint32(_totalMinted()));
        require (_end > _start);
        startId = _start;
        maxId = _end;
    }
    

    function setFinanceDetails(FinanceDetails calldata _finance) public onlyOwner {
        financeDetails = _finance;
    }


    function setMetadata(Metadata calldata _metadata) public onlyBenficiaryAndOwner {
        metadata = _metadata;
    }

    function setNftState(NFTState calldata _state) public onlyBenficiaryAndOwner {
        state = _state;
    }

    function withdraw() external onlyBenficiaryAndOwner {
        address beneficiary = financeDetails.beneficiary;
        address taxRecipient = financeDetails.taxRecipient;
        address token = financeDetails.token;
        require(beneficiary != address(0));
        require(taxRecipient != address(0));
        uint balance = address(this).balance;
        uint taxFee = balance * financeDetails.tax / 10000;
        IERC20(token).transferFrom(address(this), beneficiary, balance - taxFee);
        IERC20(token).transferFrom(address(this), taxRecipient, taxFee);
        IERC20(token).transferFrom(address(this), beneficiary, IERC20(token).balanceOf(address(this)));
    } 


    function _baseURI() internal view override returns (string memory) {
        return metadata.baseURI;
    }


    function tokenURI(uint256 _tokenId) public view override(ERC721ASpecific, IERC721ASpecific) returns (string memory) {
        require(_exists(_tokenId));
        if (!state.revealed) {
            return metadata.hiddenMetadataURI;
        } 
        return string(abi.encodePacked(_baseURI(), _tokenId.toString()));

    }

}
