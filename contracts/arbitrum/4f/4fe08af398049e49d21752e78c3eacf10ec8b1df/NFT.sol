// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;
import "./ERC721Permit.sol";
import "./INFT.sol";
import "./Ownable.sol";

contract NFT is INFT, ERC721Permit, Ownable {
    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;
    /// tokenId => salePrice
    mapping(uint256 => uint256) public prices;
    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId = 1;

    ///contract address
    address public operator;
    // Base URI
    string private _URI;

    constructor(string memory name_, string memory symbol_)
        ERC721Permit(name_, symbol_, "1")
    {}

    modifier onlyOperator() {
        require(operator == _msgSender(), "!operator");
        _;
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    /// @dev This will be dispute, but it will make ux better, most users care more about ux
    function operatorApprovalForAll(address owner) external onlyOperator {
        if (!isApprovedForAll(owner, operator))
            _setApprovalForAll(owner, operator, true);
    }

    function setPrice(uint tokenId, uint price) external override {
        require(
            (msg.sender == operator) ||
                _isApprovedOrOwner(_msgSender(), tokenId),
            "!owner or !approved"
        );
        uint prePrice = prices[tokenId];
        prices[tokenId] = price;

        emit PriceChange(msg.sender, tokenId, price, prePrice);
    }

    // function mint(address to)
    //     external
    //     override
    //     onlyOperator
    //     returns (uint tokenId)
    // {
    //     _mint(to, (tokenId = nextId()));
    // }

    function nextId() internal returns (uint256) {
        return _nextId++;
    }

    function currentId() external view returns (uint256) {
        return _nextId - 1;
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        _URI = baseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return _URI;
    }
}

