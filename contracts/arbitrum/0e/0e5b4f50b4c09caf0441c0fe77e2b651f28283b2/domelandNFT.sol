// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;


import "./ERC721URIStorage.sol";
import "./ERC721Enumerable.sol";
import "./Strings.sol";
import "./Base64.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";


import "./genTool.sol";



//contract Domeland is ReentrancyGuard, ERC721URIStorage, Ownable{
contract Domeland is ReentrancyGuard, ERC721Enumerable, ERC721URIStorage, Ownable{
    GenTool genTool;
    using SafeMath for uint256;
    using Strings for uint256;
    using Counters for Counters.Counter;


    mapping(address => bool) private _holders;

    event Minted(address indexed to, uint256 indexed tokenId);
    event GiftSent(address indexed to, uint256 amount);


    uint256 public constant MAX_TOKENS = 10000;
    uint256 public constant MAX_AMOUNT = 20; // 设置一次最多mint的NFT数量
    uint256 public _mintPrice = 0.001 ether; // 默认mint费用为0.1 ETH

    Counters.Counter private _tokenIds;

    // 添加动画合约变量 animation_url
    string public animation_url;
    string public animation_ext;

    constructor() ERC721("Domeland", "DLND") {  
         genTool = new GenTool();  
         animation_url = ""; // 初始值为空字符串
         animation_ext = ""; // 初始值为 GLTF
    }


    // 重写 _burn 函数
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }


    function mint(uint256 amount) public payable nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= MAX_AMOUNT, "Amount exceeds maximum limit");
        require(msg.value >= _mintPrice * amount, "Insufficient payment");

        for (uint256 i = 0; i < amount; i++) {
            _tokenIds.increment();
            uint256 newTokenId = _tokenIds.current();

            require(newTokenId <= MAX_TOKENS, "Token ID exceeds limit");
            require(!_exists(newTokenId), "Token already minted");

            _safeMint(msg.sender, newTokenId);
            emit Minted(msg.sender, newTokenId);
        }

        // 退还多余的支付
        uint256 refund = msg.value - _mintPrice * amount;
        if (refund > 0) {
            (bool success, ) = msg.sender.call{value: refund}("");
            require(success, "Refund failed");
        }

        _holders[msg.sender] = true;
    }


    function mintTo(address to, string memory uri) public onlyOwner {
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        _holders[to] = true; 
    }


 //   function tokenURI(uint256 tokenId) public view override returns (string memory) {
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        require(_exists(tokenId), "Token does not exist");

        string memory svg = genTool.generateSVG(tokenId);
        string memory metadata = genTool.generateMetadata(tokenId, svg);

                // 当 animation_url 不为空时，调用 genTool.generateMetadata(tokenId, svg, animation_url)
        if (bytes(animation_url).length > 0) {
            metadata = genTool.generateMetadata(tokenId, svg, animation_url, animation_ext);
        } else {
            metadata = genTool.generateMetadata(tokenId, svg);
        }


        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(metadata))
        ));
    }


    function gift(address to, uint256 amount) public onlyOwner {
        require(amount > 0, "Amount must be greater than 0");

        for (uint256 i = 0; i < amount; i++) {
            _tokenIds.increment();
            uint256 newTokenId = _tokenIds.current();
            require(newTokenId <= MAX_TOKENS, "Token ID exceeds limit");
            require(!_exists(newTokenId), "Token already minted");
            _safeMint(to, newTokenId);
        }
 
        // Emit the GiftSent event
        emit GiftSent(to, amount);

        // Update the _holders mapping
         _holders[to] = true;
    }

    function setMintPrice(uint256 newMintPrice) public onlyOwner {
        _mintPrice = newMintPrice;
    }

        // 添加 setAnimationUrl 函数，允许合约 owner 设置 animation_url
    function setAnimationUrl(string memory newUrl) public onlyOwner {
        animation_url = newUrl;
    }

    // 添加 setAnimationExt 函数，允许合约 owner 设置 animation_ext
    function setAnimationExt(string memory newExt) public onlyOwner {
        animation_ext = newExt;
    }

    // 添加withdraw函数，允许owner提款
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Withdraw failed");
    }


    // 重写 _beforeTokenTransfer 函数
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchId) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchId);
    }

 
    // 重写 supportsInterface 函数
    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }


}
