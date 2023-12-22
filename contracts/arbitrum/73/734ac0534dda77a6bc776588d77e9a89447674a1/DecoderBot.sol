// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./IERC20.sol";
import "./ERC721Enumerable.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";

contract DecoderBot is ERC721Enumerable, Ownable {
    using Strings for uint256;

    error BadInput();
    error Forbidden();
    error OutOfStock();
    error Underpaid();

    string private baseURI;
    uint256 public maxSupply;
    uint256 public price;

    uint256 private totalSupply_ = 0;
    uint256 private revealed = 0;

    enum Sale {
        PAUSED,
        PRESALE,
        PUBSALE
    }

    Sale public sale;
    mapping(address => bool) private presales;
    bytes32 private merkleRoot;
    address private operator;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        uint256 _maxSupply,
        uint256 _price
    ) ERC721(_name, _symbol) {
        baseURI = _baseURI;
        maxSupply = _maxSupply;
        price = _price;
        operator = msg.sender;
    }

    function setBaseURI(string calldata _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        if (_maxSupply < totalSupply_) revert BadInput();
        maxSupply = _maxSupply;
    }

    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setSale(Sale _sale) external onlyOwner {
        sale = _sale;
    }

    function setRevealed(uint256 _id) external onlyOwner {
        if (_id < revealed) revert BadInput();
        revealed = _id;
    }

    modifier costs(uint256 _amount) {
        if (msg.value < _amount) revert Underpaid();
        _;
    }

    function drop(address[] calldata _to, uint256[] calldata _quantity)
        external
    {
        if (msg.sender != operator) revert Forbidden();
        if (_to.length != _quantity.length) revert BadInput();

        unchecked {
            for (uint256 i = 0; i < _to.length; i++) {
                deliver(_to[i], _quantity[i]);
            }
        }
    }

    function presale(bytes32[] calldata _proof) external payable costs(price) {
        if (sale != Sale.PRESALE) revert Forbidden();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        bool isValidLeaf = MerkleProof.verify(_proof, merkleRoot, leaf);
        if (!isValidLeaf) revert Forbidden();

        deliver(msg.sender, 1);
    }

    function mint(address _to, uint256 _quantity)
        external
        payable
        costs(price * _quantity)
    {
        if (sale != Sale.PUBSALE) revert Forbidden();
        deliver(_to, _quantity);
    }

    function presold(address _to) public view returns (bool) {
        return presales[_to];
    }

    function deliver(address _to, uint256 _quantity) internal {
        if (totalSupply_ + _quantity > maxSupply) revert OutOfStock();

        if (sale == Sale.PRESALE) {
            if (presold(_to)) revert Forbidden();
            presales[_to] = true;
        }

        unchecked {
            for (uint256 i = 0; i < _quantity; i++) {
                _safeMint(_to, ++totalSupply_);
            }
        }
    }

    function withdraw(address payable recipient, uint256 amount)
        external
        onlyOwner
    {
        recipient.transfer(amount);
    }

    function withdraw(
        address recipient,
        address erc20,
        uint256 amount
    ) external onlyOwner {
        IERC20(erc20).transfer(recipient, amount);
    }

    function totalSupply() public view override returns (uint256) {
        return totalSupply_;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        uint256 _id = tokenId <= revealed ? tokenId : 0;

        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, _id.toString(), ".json"))
                : "";
    }
}

