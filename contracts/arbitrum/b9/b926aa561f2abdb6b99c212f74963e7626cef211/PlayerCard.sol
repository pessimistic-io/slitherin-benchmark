// SPDX-License-Identifier: MIT
//  ______           _                ______             _          _
// (_____ \      _  (_)              (_____ \           (_)        | |
//  _____) )__ _| |_ _  ___  ____     _____) )____ ____  _  ____   | |
// |  ____/ _ (_   _) |/ _ \|  _ \   |  ____(____ |  _ \| |/ ___)  |_|
// | |   | |_| || |_| | |_| | | | |  | |    / ___ | | | | ( (___    _
// |_|    \___/  \__)_|\___/|_| |_|  |_|    \_____|_| |_|_|\____)  |_|
//

pragma solidity >=0.8.0;

import {Operatable} from "./Operatable.sol";
import {IPlayerCardDescriptor} from "./IPlayerCardDescriptor.sol";
import {IPlayerCard} from "./IPlayerCard.sol";

/// @notice PotionPanic Player Card / Soulbound NFT
/// @author 0xCalibur
contract PlayerCard is IPlayerCard, Operatable {
    error ErrAlreadyMinted();
    error ErrNotMinted();
    error ErrZeroAddress();
    error ErrUnsupported();

    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event DescriptorChanged(IPlayerCardDescriptor indexed descriptor);
    event OwnerDataUpdated(uint256 indexed owner, bytes data);

    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) public idOf;

    uint256 public totalSupply;
    IPlayerCardDescriptor public descriptor;
    mapping(uint256 => bytes) public ownerData;

    constructor(address _owner) Operatable(_owner) {}

    function name() public pure returns (string memory) {
        return "PotionPanicCard";
    }

    function symbol() public pure returns (string memory) {
        return "PotionPanicCard";
    }

    function ownerOf(uint256 id) public view returns (address owner) {
        if ((owner = _ownerOf[id]) == address(0)) {
            revert ErrNotMinted();
        }
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        if (_ownerOf[id] == address(0)) {
            revert ErrNotMinted();
        }

        return IPlayerCardDescriptor(descriptor).tokenURI(this, id);
    }

    function balanceOf(address _owner) public view returns (uint256) {
        if (_owner == address(0)) {
            revert ErrZeroAddress();
        }

        return idOf[_owner] == 0 ? 0 : 1;
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    function mint() external returns (uint256) {
        return mint(msg.sender);
    }

    function mint(address to) public returns (uint256 id) {
        if (idOf[to] != 0) {
            revert ErrAlreadyMinted();
        }

        id = ++totalSupply;

        idOf[to] = id;
        _ownerOf[id] = to;
        emit Transfer(address(0), to, id);
    }

    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-
    /// Operators Functions
    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-
    function updateOwnerData(address owner, bytes memory data) external onlyOperators {
        uint256 id = idOf[owner];
        if (id == 0) {
            revert ErrNotMinted();
        }

        ownerData[id] = data;
        emit OwnerDataUpdated(id, data);
    }

    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-
    /// Admin Functions
    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-

    function setDescriptor(IPlayerCardDescriptor _descriptor) external onlyOwner {
        descriptor = _descriptor;
        emit DescriptorChanged(_descriptor);
    }

    fallback() external {
        revert ErrUnsupported();
    }
}

