//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ClonesUpgradeable } from "./ClonesUpgradeable.sol";
import "./ContextUpgradeable.sol";
import "./interfaces_IOSBFactory.sol";
import "./interfaces_ISetting.sol";
import "./contracts-exposed_OSB721.sol";
import "./contracts-exposed_OSB1155.sol";

contract OSBFactory is ContextUpgradeable {
    uint256 public lastId;
    address public library721Address;
    address public library1155Address;

    ISetting public setting;

    mapping(address => bool) public controllers;
    mapping(uint256 => TokenInfo) public tokenInfos;
    
    function initialize(address _settingAddress, address _library721Address, address _library1155Address) external initializer {
        require(_settingAddress != address(0), "Invalid settingAddress");
        require(_library721Address != address(0), "Invalid library721Address");
        require(_library1155Address != address(0), "Invalid library1155Address");
        setting = ISetting(_settingAddress);
        library721Address = _library721Address;
        library1155Address = _library1155Address;
    }

    modifier onlySuperAdmin() {
        setting.checkOnlySuperAdmin(_msgSender());
        _;
    }

    event Create(uint256 indexed id, TokenInfo tokenInfo);
    event SetLibraryAddress(address indexed oldAddress, address indexed newAddress);

    function setLibrary721Address(address _library721Address) external onlySuperAdmin {
        require(_library721Address != address(0), "Invalid library721Address");
        address oldAddress = library721Address;
        library721Address = _library721Address;
        emit SetLibraryAddress(oldAddress, _library721Address);
    }

    function setLibrary1155Address(address _library1155Address) external onlySuperAdmin {
        require(_library1155Address != address(0), "Invalid library1155Address");
        address oldAddress = library1155Address;
        library1155Address = _library1155Address;
        emit SetLibraryAddress(oldAddress, _library1155Address);
    }
  
    function create(bool _isSingle, string memory _baseUri, string memory _name, string memory _symbol, address _royaltyReceiver, uint96 _royaltyFeeNumerator) external returns (TokenInfo memory) {
        lastId++;
        bytes32 salt = keccak256(abi.encodePacked(lastId));
        address deployedContract;

        if (_isSingle) {
            OSB721 _osb721 = OSB721(ClonesUpgradeable.cloneDeterministic(library721Address, salt));
            _osb721.initialize(_msgSender(), _baseUri, _name, _symbol, _royaltyReceiver, _royaltyFeeNumerator); 
            deployedContract = address(_osb721);
        } else {
            OSB1155 _osb1155 = OSB1155(ClonesUpgradeable.cloneDeterministic(library1155Address, salt));
            _osb1155.initialize(_msgSender(), _baseUri, _name, _symbol, _royaltyReceiver, _royaltyFeeNumerator); 
            deployedContract = address(_osb1155);
        }

        TokenInfo storage tokenInfo = tokenInfos[lastId];
        tokenInfo.token = deployedContract;
        tokenInfo.owner = _msgSender();
        tokenInfo.receiverRoyaltyFee = _royaltyReceiver;
        tokenInfo.percentageRoyaltyFee = _royaltyFeeNumerator;
        tokenInfo.baseURI = _baseUri;
        tokenInfo.name = _name;
        tokenInfo.symbol = _symbol;
        tokenInfo.isSingle = _isSingle;

        emit Create(lastId, tokenInfo);
        return tokenInfo;
    }
}

