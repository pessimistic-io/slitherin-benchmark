//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./ERC1155Upgradeable.sol";
import "./ERC2981Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./StringsUpgradeable.sol";

contract OSB1155 is ERC1155Upgradeable, ERC2981Upgradeable, OwnableUpgradeable {
    using StringsUpgradeable for uint256;

    uint256 public lastId;
    string public name;
    string public symbol;
    string public baseURI;
    RoyaltyInfo public defaultRoyaltyInfo;

    mapping(address => bool) public controllers;

    event MintBatch(string indexed oldUri, string indexed newUri, uint256[] tokenIds, uint256[] amounts);
    event MintBatchWithRoyalty(string indexed oldUri, string indexed newUri, uint256[] tokenIds, uint256[] amounts, address[] receiverRoyaltyFees, uint96[] percentageRoyaltyFees);
    event SetController(address indexed account, bool allow);
    event SetBaseURI(string indexed oldUri, string indexed newUri);

    modifier onlyOwnerOrController() {
        require(_msgSender() == owner() || controllers[_msgSender()], "Caller is not the owner or controller");
        _;
    }

    // called once by the factory at time of deployment
    function initialize(address _owner, string memory _baseUri, string memory _name, string memory _symbol, address _receiverRoyaltyFee, uint96 _percentageRoyaltyFee) public initializer {
        __ERC1155_init("");
        __Ownable_init();
        transferOwnership(_owner);

        baseURI = _baseUri;
        name = _name;
        symbol = _symbol;
        
        if (_receiverRoyaltyFee != address(0)) {
            require(_percentageRoyaltyFee > 0, "Invalid percentageRoyaltyFee");
            defaultRoyaltyInfo = RoyaltyInfo(_receiverRoyaltyFee, _percentageRoyaltyFee);
            _setDefaultRoyalty(_receiverRoyaltyFee, _percentageRoyaltyFee);
        }
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155Upgradeable, ERC2981Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function uri(uint256 _tokenId) public view override returns (string memory) {
        string memory _baseURI = baseURI;
        return bytes(_baseURI).length > 0 ? string(abi.encodePacked(_baseURI, _tokenId.toString(), ".json")) : ".json";
    }

    function setBaseURI(string memory _newUri) external onlyOwnerOrController {
        string memory oldUri = baseURI;
        baseURI = _newUri;
        emit SetBaseURI(oldUri, _newUri);
    }

    function mint(address _to, uint256 _amount) external onlyOwnerOrController returns (uint256) {
        lastId++;
        _mint(_to, lastId, _amount, "");
        return lastId;
    }

    function mintWithRoyalty(address _to, uint256 _amount, address _receiverRoyaltyFee, uint96 _percentageRoyaltyFee) external onlyOwnerOrController returns (uint256) {
        lastId++;
        _mint(_to, lastId, _amount, "");
        if (_receiverRoyaltyFee == address(0)) _setTokenRoyalty(lastId, defaultRoyaltyInfo.receiver, _percentageRoyaltyFee);
        else _setTokenRoyalty(lastId, _receiverRoyaltyFee, _percentageRoyaltyFee);
        return lastId;
    }

    function mintBatch(string memory _baseUri, uint256[] memory _amounts) external onlyOwnerOrController {
        require(_amounts.length > 0, "Invalid amounts");
        uint256 id = lastId;
        uint256[] memory tokenIds = new uint256[](_amounts.length);
        string memory oldUri = baseURI;
        for (uint256 i; i < _amounts.length; i++) {
            tokenIds[i] = id++;
            _mint(_msgSender(), id, _amounts[i], "");
        }
        baseURI = _baseUri;
        lastId = id;
        emit MintBatch(oldUri, _baseUri, tokenIds, _amounts);
    }

    function mintBatchWithRoyalty(string memory _baseUri, uint256[] memory _amounts, address[] memory _receiverRoyaltyFees, uint96[] memory _percentageRoyaltyFees) external onlyOwnerOrController {
        require(_amounts.length == _receiverRoyaltyFees.length && _receiverRoyaltyFees.length == _percentageRoyaltyFees.length, "Invalid pram");
        require(_amounts.length > 0, "Invalid amounts");
        uint256 id = lastId;
        uint256[] memory tokenIds = new uint256[](_amounts.length);
        string memory oldUri = baseURI;
        for (uint256 i; i < _amounts.length; i++) {
            tokenIds[i] = id++;
            _mint(_msgSender(), id, _amounts[i], "");
            if (_percentageRoyaltyFees[i] == 0) continue;
            if (_receiverRoyaltyFees[i] == address(0)) _setTokenRoyalty(id, defaultRoyaltyInfo.receiver, _percentageRoyaltyFees[i]);
            else _setTokenRoyalty(id, _receiverRoyaltyFees[i], _percentageRoyaltyFees[i]);
        }
        baseURI = _baseUri;
        lastId = id;
        emit MintBatchWithRoyalty(oldUri, _baseUri, tokenIds, _amounts, _receiverRoyaltyFees, _percentageRoyaltyFees);
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

