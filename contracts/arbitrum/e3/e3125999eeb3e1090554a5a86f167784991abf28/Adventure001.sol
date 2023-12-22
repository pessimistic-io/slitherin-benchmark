// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./IERC20.sol";
import "./ERC721Enumerable.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";

contract Adventure001 is ERC721Enumerable, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 500;
    uint256 private constant PRESALE_CAP = 100;
    uint256 private _totalSupply = 0;
    uint256 private _totalPresale = 0;
    mapping(address => bool) private presales;
    enum Sale {
        PAUSED,
        PRESALE,
        PUBLIC
    }
    Sale public sale;
    uint256 public price;
    bool private revealed;
    string public provenance;
    string private baseURI;
    bytes32 private merkleRoot;
    address private operator;

    error BadInput();
    error BeepBoop();
    error Forbidden();
    error OutOfStock();
    error Underpaid();

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {
        operator = msg.sender;
    }

    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function setBaseURI(string calldata _baseURI) external onlyOwner {
        baseURI = _baseURI;
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

    function reveal(string calldata _provenance) external onlyOwner {
        if (revealed) revert Forbidden();

        revealed = true;
        provenance = _provenance;
    }

    modifier eoaOnly() {
        if (tx.origin != msg.sender) revert BeepBoop();
        _;
    }

    modifier costs(uint256 _price) {
        if (msg.value < _price) revert Underpaid();
        _;
        if (msg.value > _price) {
            payable(msg.sender).transfer(msg.value - _price);
        }
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

    function presale(bytes32[] calldata _proof)
        external
        payable
        costs(price)
        eoaOnly
    {
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
        eoaOnly
    {
        if (sale != Sale.PUBLIC) revert Forbidden();

        deliver(_to, _quantity);
    }

    function deliver(address to, uint256 quantity) internal {
        if (_totalSupply + quantity > MAX_SUPPLY) revert OutOfStock();

        if (sale == Sale.PRESALE) {
            if (_totalPresale + quantity > PRESALE_CAP) revert OutOfStock();
            if (presales[to]) revert Forbidden();
            _totalPresale += quantity;
            presales[to] = true;
        }

        unchecked {
            for (uint256 i = 0; i < quantity; i++) {
                _safeMint(to, ++_totalSupply);
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
        return _totalSupply;
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

        uint256 _id;

        if (tokenId <= 7) {
            _id = tokenId;
        } else {
            _id = revealed ? tokenId : 0;
        }

        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, _id.toString(), ".json"))
                : "";
    }
}

