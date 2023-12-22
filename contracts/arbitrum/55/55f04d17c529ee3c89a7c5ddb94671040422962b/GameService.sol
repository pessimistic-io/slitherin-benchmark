// SPDX-License-Identifier: MIT
// Metaline Contracts (GameService.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./Context.sol";

import "./MTT.sol";
import "./MTTGold.sol";
import "./HeroNFT.sol";
import "./ShipNFT.sol";
import "./WarrantNFT.sol";

import "./Crypto.sol";
import "./TransferHelper.sol";

contract GameService is
    Context,
    Pausable,
    AccessControl 
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    event BindHeroNFTUsage(address indexed userAddr, uint256 indexed heroNFTID, string usage);
    event UnbindHeroNFTUsage(address indexed userAddr, uint256 indexed heroNFTID, string usage);
    event BindShipNFT(address indexed userAddr, uint256 indexed shipNFTID);
    event UnbindShipNFT(address indexed userAddr, uint256 indexed shipNFTID);
    event BindWarrant(address indexed userAddr, uint256 indexed warrantNFTID);
    event UnbindWarrant(address indexed userAddr, uint256 indexed warrantNFTID);
    
    address public _heroNFTAddr;
    address public _shipNFTAddr;
    address public _warrantNFTAddr;
    address public _MTTAddr;
    address public _MTTGoldAddr;

    mapping(uint256=>bytes32) public _heroNFTUsage; // nftid => usage
    mapping(uint256=>bool) public _shipNFTBind; // nftid => is bind

    mapping(address=>mapping(uint32=>uint256)) public _bindWarrant; // user address => port id => warrant id

//    address public _serviceAddr;
//    mapping(address=>uint64) public _userOpSignatureSeed; // user address => signature seed

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(MANAGER_ROLE, _msgSender());
        _setupRole(SERVICE_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
    }

    function pause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "GameService: must have pauser role to pause"
        );
        _pause();
    }

    function unpause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "GameService: must have pauser role to unpause"
        );
        _unpause();
    }
    
    function init(
//        address serviceAddr,
        address heroNFTAddr,
        address shipNFTAddr,
        address warrantNFTAddr,
        address MTTAddr,
        address MTTGoldAddr
    ) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "GameService: must have manager role");

//        _serviceAddr = serviceAddr;
        _heroNFTAddr = heroNFTAddr;
        _shipNFTAddr = shipNFTAddr;
        _warrantNFTAddr = warrantNFTAddr;
        _MTTAddr = MTTAddr;
        _MTTGoldAddr = MTTGoldAddr;
    }

    function bindHeroNFTUsage(uint256 heroNFTID, string calldata usage) external whenNotPaused {
        require(HeroNFT(_heroNFTAddr).ownerOf(heroNFTID) == _msgSender(), "GameService: ownership error");
        require(_heroNFTUsage[heroNFTID] == bytes32(0), "GameService: already binded");

        HeroNFT(_heroNFTAddr).freeze(heroNFTID);

        _heroNFTUsage[heroNFTID] = keccak256(abi.encodePacked(usage));

        emit BindHeroNFTUsage(_msgSender(), heroNFTID, usage);
    }

    function unbindHeroNFTUsage(
        uint256 heroNFTID, 
        string calldata usage,
        address userAddr
        //bytes calldata serviceSignature
        ) external whenNotPaused
    {
        require(hasRole(SERVICE_ROLE, _msgSender()), "GameService: must have service role");

        require(HeroNFT(_heroNFTAddr).ownerOf(heroNFTID) == userAddr, "GameService: ownership error");
        require(_heroNFTUsage[heroNFTID] != bytes32(0), "GameService: nft usage not exist");

        // uint64 sigSeed = _userOpSignatureSeed[_msgSender()];
        // _userOpSignatureSeed[_msgSender()] = sigSeed + 1;

        // require(Crypto.verifySignature(abi.encodePacked("unbind", _msgSender(), heroNFTID, sigSeed), serviceSignature, _serviceAddr), "GameService: wrong signature");

        HeroNFT(_heroNFTAddr).unfreeze(heroNFTID);
        delete _heroNFTUsage[heroNFTID];

        emit UnbindHeroNFTUsage(userAddr, heroNFTID, usage);
    }
    
    function bindShipNFT(uint256 shipNFTID) external whenNotPaused {
        require(HeroNFT(_shipNFTAddr).ownerOf(shipNFTID) == _msgSender(), "GameService: ownership error");
        require(!_shipNFTBind[shipNFTID], "GameService: already binded");

        ShipNFT(_shipNFTAddr).freeze(shipNFTID);

        _shipNFTBind[shipNFTID] = true;

        emit BindShipNFT(_msgSender(), shipNFTID);
    }

    function unbindShipNFT(
        uint256 shipNFTID,
        uint16 portID,
        address userAddr
    ) external whenNotPaused
    {
        require(hasRole(SERVICE_ROLE, _msgSender()), "GameService: must have service role");

        require(ShipNFT(_shipNFTAddr).ownerOf(shipNFTID) == userAddr, "GameService: ownership error");
        require(_shipNFTBind[shipNFTID], "GameService: nft not bind");

        ShipNFT(_shipNFTAddr).modNftPort(shipNFTID, portID);
        
        ShipNFT(_shipNFTAddr).unfreeze(shipNFTID);
        delete _shipNFTBind[shipNFTID];

        emit UnbindShipNFT(userAddr, shipNFTID);
    }
    
    function bindWarrant(uint256 warrantNFTID) external whenNotPaused {
        require(WarrantNFT(_warrantNFTAddr).ownerOf(warrantNFTID) == _msgSender(), "GameService: ownership error");

        // get warrant nft data
        WarrantNFTData memory wdata = WarrantNFT(_warrantNFTAddr).getNftData(warrantNFTID);
        require(_bindWarrant[_msgSender()][wdata.portID] == 0, "GameService: already bind");

        // bind
        _bindWarrant[_msgSender()][wdata.portID] = warrantNFTID;
        WarrantNFT(_warrantNFTAddr).freeze(warrantNFTID);

        emit BindWarrant(_msgSender(), warrantNFTID);
    }

    function unbindWarrant(
        uint256 warrantNFTID, 
        address userAddr
    ) external whenNotPaused{
        require(hasRole(SERVICE_ROLE, _msgSender()), "GameService: must have service role");
        require(WarrantNFT(_warrantNFTAddr).ownerOf(warrantNFTID) == userAddr, "GameService: ownership error");

        // get warrant nft data
        WarrantNFTData memory wdata = WarrantNFT(_warrantNFTAddr).getNftData(warrantNFTID);
        require(_bindWarrant[userAddr][wdata.portID] == warrantNFTID, "GameService: warrant bind addr error");

        // unbind
        WarrantNFT(_warrantNFTAddr).unfreeze(warrantNFTID);
        delete _bindWarrant[userAddr][wdata.portID];

        emit UnbindWarrant(userAddr, warrantNFTID);
    }
}
