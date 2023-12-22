// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./DefaultOperatorFilterer.sol";

interface IGBT {
    function currentPrice() external view returns (uint256);
    function getProtocol() external view returns (address);
    function initSupply() external view returns (uint256);
    function artist() external view returns (address);
}

contract GNFT is ERC721Enumerable, DefaultOperatorFilterer, ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    Counters.Counter private _tokenIdCounter;

    // Fee
    uint256 public immutable bFee; // redemption fee
    uint256 public constant DIVISOR = 1000;

    // Token
    string public baseTokenURI;
    
    // Protocol
    address public immutable GBT;
    string public _contractURI;
    uint256 public immutable maxSupply;

    mapping (uint256 => int256) public gumballIndex;
    uint256[] public gumballs;

    event Swap(address indexed user, uint256 amount);
    event ExactSwap(address indexed user, uint256[] id);
    event Redeem(address indexed user, uint256[] id);
    event SetBaseURI(string uri);
    event SetContractURI(string uri);

    constructor(
        string memory name,
        string memory symbol,
        string[] memory _URIs,
        address _GBT,
        uint256 _bFee
        ) ERC721(name, symbol) {
        require(_bFee <= 100, "Redemption fee too high");
        baseTokenURI = _URIs[0];
        _contractURI = _URIs[1];
        GBT = _GBT;
        bFee = _bFee;
        maxSupply = IGBT(GBT).initSupply() / 1e18;
    }

    ////////////////////
    ////// Public //////
    ////////////////////

    function gumballsLength() external view returns (uint256) {
        return gumballs.length;
    }

    function owner() external view returns (address) {	
        return IGBT(GBT).artist();	
    }

    /** Returns bal of {GBT} */
    function tokenBal() external view returns (uint256) {
        return IERC20(GBT).balanceOf(address(this));
    }

    /** Returns bal of {Gumball} */
    function nftBal() external view returns (uint256) {
        return balanceOf(address(this));
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function currentPrice() external view returns (uint256) {
        return IGBT(GBT).currentPrice();
    }

    //////////////////////
    ////// External //////
    //////////////////////

    /** @dev Allows user to swap {GBT} for an exact {Gumball} that has already been minted
      * @param id is an array of {Gumball}s the user is swapping for 
    */
    function swapForExact(uint256[] calldata id) external nonReentrant {
        require(IERC20(GBT).balanceOf(msg.sender) >= enWei(id.length), "Insuffient funds");
        require(id.length != 0, "Parameter length cannot be zero");

        uint256 before = IERC20(GBT).balanceOf(address(this));

        for(uint256 i = 0; i < id.length; i ++) {
            require(gumballIndex[id[i]] != -1, "NFT removed from mapping, sentinel number (-1)");
            _pop(uint256(gumballIndex[id[i]]));
            gumballIndex[id[i]] = -1;
            IERC721(address(this)).transferFrom(address(this), msg.sender, id[i]);
        }
        
        IERC20(GBT).safeTransferFrom(msg.sender, address(this), enWei(id.length));
        require(IERC20(GBT).balanceOf(address(this)) >= before + enWei(id.length), "Contract balance underflow");

        emit ExactSwap(msg.sender, id);
    }

    /** @dev Allows the user to swap a quantity of {token} > 1 
      * @param _amount is the number of tokens to mint 
    */
    function swap(uint256 _amount) external nonReentrant {
        require(enETH(_amount) * 1e18 == _amount, "Whole GBTs only");
        require(IERC20(GBT).balanceOf(msg.sender) >= enWei(1), "Insuffient funds");
        require(_amount > 0, "Amount cannot be zero");

        uint256 before = IERC20(GBT).balanceOf(address(this));

        IERC20(GBT).safeTransferFrom(msg.sender, address(this), _amount);

        for(uint256 i = 0; i < enETH(_amount); i++) {
            mint(msg.sender);
        }
        require(IERC20(GBT).balanceOf(address(this)) >= before + _amount, "Contract balance underflow");

        emit Swap(msg.sender, _amount);
    }

    /** @dev Allows user to swap their gumball(s) to the contract for a payout of {GBT} 
      * @param _id is an array of ids of the gumball token(s) swapped in
    */
    function redeem(uint256[] calldata _id) external nonReentrant {
        require(IERC721(address(this)).balanceOf(msg.sender) >= _id.length, "Insuffient Balance");
        require(_id.length != 0, "Parameter length cannot be zero");

        uint256 before = IERC721(address(this)).balanceOf(address(this));
        uint256 burnAmount = enWei(_id.length) * bFee / DIVISOR;
    
        for (uint256 i = 0; i < _id.length; i++) {
            gumballs.push(_id[i]);
            gumballIndex[_id[i]] = int256(gumballs.length - 1);
            IERC721(address(this)).transferFrom(msg.sender, address(this), _id[i]);
        }

        IERC20(GBT).safeTransfer(GBT, burnAmount);
        IERC20(GBT).safeTransfer(msg.sender, enWei(_id.length) - burnAmount);

        require(IERC721(address(this)).balanceOf(address(this)) >= before + _id.length, "Bad Swap");

        emit Redeem(msg.sender, _id);
    }

    //////////////////////
    ////// Internal //////
    //////////////////////

    function enWei(uint256 _num) internal pure returns(uint256) {
        return _num * 10**18;
    }

    function enETH(uint256 _num) internal pure returns(uint256) {
        return _num / 10**18;
    }

    /** @dev Internal function to remove an unwanted index from an array */
    function _pop(uint256 _index) internal {
        uint256 tempID;
        uint256 swapID;

        if (gumballs.length > 1 && _index != gumballs.length - 1) {
            tempID = gumballs[_index];
            swapID = gumballs[gumballs.length - 1];
            gumballs[_index] = swapID;
            gumballs[gumballs.length - 1] = tempID;
            gumballIndex[swapID] = int256(_index);

            gumballs.pop();
        } else {
            gumballs.pop();
        }
    }

    /** @dev {_tokenIdTracker} counter tracks the id of next NFT
      * @param to mints to address */
    function mint(address to) internal {
        require(_tokenIdCounter.current() < maxSupply, "Max Supply Minted");
        _mint(to, _tokenIdCounter.current());
        _tokenIdCounter.increment();
    }

    /////////////////////
    ///// Overrides /////
    /////////////////////

    // The following functions are overrides required by Solidity.

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function setApprovalForAll(address operator, bool approved) public override(ERC721, IERC721) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    ////////////////////
    //// Restricted ////
    ////////////////////

    /** @dev Allows the protocol to set {baseURI}
      * @param uri is the updated URI
    */
    function setBaseURI(string calldata uri) external OnlyArtist {
        baseTokenURI = uri;

        emit SetBaseURI(uri);
    }

    /** @dev Allows the protocol to set {contractURI} 
      * @param uri is the updated URI
    */
    function setContractURI(string calldata uri) external OnlyArtist {
        _contractURI = uri;

        emit SetContractURI(uri);
    }

    modifier OnlyArtist() {
        require(msg.sender == IGBT(GBT).artist(), "!AUTH");
        _;
    }
}

contract GNFTFactory {
    address public factory;
    address public lastGNFT;

    event FactorySet(address indexed _factory);

    constructor() {
        factory = msg.sender;
    }

    function setFactory(address _factory) external OnlyFactory {
        factory = _factory;
        emit FactorySet(_factory);
    }

    function createGNFT(
        string memory _name,
        string memory _symbol,
        string[] memory _URIs,
        address _GBT, 
        uint256 _bFee
    ) external OnlyFactory returns (address) {
        GNFT newGNFT = new GNFT(_name, _symbol, _URIs, _GBT, _bFee);
        lastGNFT = address(newGNFT);
        return lastGNFT;
    }

    modifier OnlyFactory() {
        require(msg.sender == factory, "!AUTH");
        _;
    }
}
