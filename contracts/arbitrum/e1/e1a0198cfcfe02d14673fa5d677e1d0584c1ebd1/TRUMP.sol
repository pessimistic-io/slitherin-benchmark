// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./ERC721Enumerable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./IERC2981.sol";
import "./Strings.sol";
import "./ReentrancyGuard.sol";

import {DefaultOperatorFilterer} from "./DefaultOperatorFilterer.sol";

interface ITrump  {
    function tokenExists(uint256 tokenId) external view returns (bool);

}

contract TRUMP is ITrump, ERC721Enumerable, DefaultOperatorFilterer, IERC2981, AccessControl,Ownable, ReentrancyGuard {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    struct share_data {
        uint16 share;
        address payee;
    }


    bytes32 public constant MINTER_ROLE    = keccak256(   "MINTER_ROLE");
    bytes32 public constant CONTRACT_ADMIN = keccak256("CONTRACT_ADMIN");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
 
    uint16       constant       internal    collectionRoyaltyAmount = 20;
    string                      private     collectionURI;
    uint16                      public      nextToken = 1;
    string                      public      tokenBaseURI;
    bool                        public      frozen;
    uint256                     public      cost = 0.04 ether;

    event ContractURIChanged(string uri);
    event BaseURI(string baseURI);
    event WithdrawnBatch(address indexed user, uint256[] tokenIds);
    event PaymentReceived(uint256 value);
    event MetadataFrozen();


    error InvalidTokenOwner(uint256 tokenId);

    modifier isCorrectPayment(uint256 price, uint256 numberOfTokens) {
        require(
            price * numberOfTokens == msg.value,
            "Incorrect ETH value sent"
        );
        _;
    }


    constructor(
    ) ERC721("ArbiTrump", "$TRUMP")
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(CONTRACT_ADMIN, _msgSender());
        tokenBaseURI = "https://cards.collecttrumpcards.com/data/";
    }

    receive() external payable {
        emit PaymentReceived(msg.value);
    }

    function contractURI() external view returns (string memory) {
        return collectionURI;
    }


    function freeze() external onlyRole(CONTRACT_ADMIN) {
        frozen = true;
        emit MetadataFrozen();
    }


    function setBaseURI(string memory newBaseURI) external onlyRole(CONTRACT_ADMIN) {
        require(!frozen,"Collection is frozen");
        tokenBaseURI = newBaseURI;
        emit BaseURI(newBaseURI);
    }

    
    function setContractURI(string memory _uri) external onlyRole(CONTRACT_ADMIN) {
        collectionURI = _uri;
        emit ContractURIChanged(_uri);
    }

    function tokenExists(uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }



    /// IERC2981
    function royaltyInfo(uint256 , uint256 salePrice)
    external
    view
    returns (address receiver, uint256 royaltyAmount)
    {
        // calculate the amount of royalties
        uint256 _royaltyAmount = (salePrice * collectionRoyaltyAmount) / 1000; // 10%
        // return the amount of royalties and the recipient collection address
        return (address(this), _royaltyAmount);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        // reformat to directory structure as below
        string memory folder = (tokenId / 1000).toString(); 
        string memory file = tokenId.toString();
        string memory slash = "/";
        return string(
            abi.encodePacked(
                tokenBaseURI,
                folder,
                slash,
                file,
                ".json")
            );
    }
 
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC721Enumerable, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721Enumerable).interfaceId ||
            interfaceId == type(AccessControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            super.supportsInterface(interfaceId);
    }


    function mint(uint8 n)
    public
    payable 
    isCorrectPayment(cost, n)
    nonReentrant
    {
        uint256 pos = nextToken;
        nextToken += n;
        for (uint256 j = 0; j < n; j++) {
            _mint(msg.sender, pos++);
        }
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }


    // opensea stuff

    function transferFrom(address from, address to, uint256 tokenId) public override  (ERC721, IERC721) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override  (ERC721, IERC721) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override (ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }


}
