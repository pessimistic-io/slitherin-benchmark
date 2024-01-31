//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ERC2981Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./StringsUpgradeable.sol";

contract OSB721 is ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC2981Upgradeable, OwnableUpgradeable {
    using StringsUpgradeable for uint256;

    uint256 public lastId;
    string  public baseURI;
    RoyaltyInfo public defaultRoyaltyInfo;

    mapping(address => bool) public controllers;

    event MintBatch(string indexed oldUri, string indexed newUri, uint256[] tokenIds);
    event MintBatchWithRoyalty(string indexed oldUri, string indexed newUri, uint256[] tokenIds, address[] receiverRoyaltyFees, uint96[] percentageRoyaltyFees);
    event SetController(address indexed account, bool allow);
    event SetBaseURI(string indexed oldUri, string indexed newUri);

    modifier onlyOwnerOrController() {
        require(_msgSender() == owner() || controllers[_msgSender()], "Caller is not the owner or controller");
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override (ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC2981Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override (ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // called once by the factory at time of deployment
    function initialize(address _owner, string memory _baseUri, string memory _name, string memory _symbol, address _receiverRoyaltyFee, uint96 _percentageRoyaltyFee) public initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init();
        transferOwnership(_owner);
        
        baseURI = _baseUri;

        if (_receiverRoyaltyFee != address(0)) {
            require(_percentageRoyaltyFee > 0, "Invalid percentageRoyaltyFee");
            defaultRoyaltyInfo = RoyaltyInfo(_receiverRoyaltyFee, _percentageRoyaltyFee);
            _setDefaultRoyalty(_receiverRoyaltyFee, _percentageRoyaltyFee);
        }
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token.");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json")) : ".json";
    }

    function mint(address _to) external onlyOwnerOrController returns (uint256) {
        lastId++;
        _safeMint(_to, lastId);
        return lastId;
    }

    function mintWithRoyalty(address _to, address _receiverRoyaltyFee, uint96 _percentageRoyaltyFee) external onlyOwnerOrController returns (uint256) {
        lastId++;
        _safeMint(_to, lastId);
        if (_receiverRoyaltyFee == address(0)) _setTokenRoyalty(lastId, defaultRoyaltyInfo.receiver, _percentageRoyaltyFee);
        else _setTokenRoyalty(lastId, _receiverRoyaltyFee, _percentageRoyaltyFee);
        return lastId;
    }

    function mintBatch(string memory _baseUri, uint256 _times) external onlyOwnerOrController {
        require(_times > 0, "Invalid times");
        uint256 id = lastId;
        uint256[] memory tokenIds = new uint256[](_times);
        string memory oldUri = baseURI;

        for (uint256 i; i < _times; i++) {
            tokenIds[i] = ++id;
            _safeMint(_msgSender(), id);
        }

        baseURI = _baseUri;
        lastId = id;
        emit MintBatch(oldUri, _baseUri, tokenIds);
    }  

    function mintBatchWithRoyalty(string memory _baseUri, address[] memory _receiverRoyaltyFees, uint96[] memory _percentageRoyaltyFees) external onlyOwnerOrController {
        require(_receiverRoyaltyFees.length == _percentageRoyaltyFees.length, "Invalid param");
        require(_receiverRoyaltyFees.length > 0, "Invalid receiverRoyaltyFees");
        uint256 id = lastId;
        uint256[] memory tokenIds = new uint256[](_percentageRoyaltyFees.length);
        string memory oldUri = baseURI;
        for (uint256 i; i < _receiverRoyaltyFees.length; i++) {
            tokenIds[i] = id++;
            _safeMint(_msgSender(), id);
            if (_percentageRoyaltyFees[i] == 0) continue;
            if (_receiverRoyaltyFees[i] == address(0)) _setTokenRoyalty(id, defaultRoyaltyInfo.receiver, _percentageRoyaltyFees[i]);
            else _setTokenRoyalty(id, _receiverRoyaltyFees[i], _percentageRoyaltyFees[i]);
        }
        baseURI = _baseUri;
        lastId = id;
        emit MintBatchWithRoyalty(oldUri, _baseUri, tokenIds, _receiverRoyaltyFees, _percentageRoyaltyFees);
    }  

    function setBaseURI(string memory _newUri) external onlyOwnerOrController {
        string memory oldUri = baseURI;
        baseURI = _newUri;
        emit SetBaseURI(oldUri, _newUri);
    }

    /**
     * @notice Delegate controller permission to account
     * @param  _account account that set the controller
     * @param  _allow  setting value
     */
    function setController(address _account, bool _allow) external onlyOwner {
        require(_account != address(0), "Invalid account");
        require(controllers[_account] != _allow, "Duplicate setting");
        controllers[_account] = _allow;

        emit SetController(_account, _allow);
    }
}
