// SPDX-License-Identifier: Unlicense


///////////////////////////////////////////////////////////////////////////////////////////
//░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██▓██▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░▒░░▒░░░░░▒░░▒░░░░░░░░░░▓█▓▓▓██░░░░░░░░░░░▒░░▒░░░░▒░░▒░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░▒▒▒░░░░▒▒░░░░░░░░▒▒▒▒▓▒▒▒▓██▓▓▓███▓▒▒▓▒▒▒▒░░░░░░░░░▓▒░░░▒▒▒░░░░░░░░░░░░░░░//
//░░░░░░░░░░░▒▒░▓▓░░░▒▓▒░░░░▒▓░░░░▓▓██▓▓▓██▓▓▓▓█▓▓▓███▓▒░░░▒▓░░░░░▓▓░░░▒▓▒░▒▒░░░░░░░░░░░░//
//░░░░░░░░▒▒▒░░▒▓▓▒░░░▓▒░░░▒▓░░▒▓███▓▓▒▒▓██▓▓▓██▒▒▒▒▓▓██▓▒░░▒▓░░░░▓▓░░░▓▓▓░░░▒▒░░░░░░░░░░//
//░░░░░░░▓▒▒▒▒░░▓▓▓▒▒▒▓▓▒░▒▓▒▒▓██▓▓▒▒░░░▒██▓▓▓██▒▒▒▒▒▒▓▓██▓▒░▓▓░▒▓▓▒▒▒▓▓▓▒░░▒▓▒▒▒░░░░░░░░//
//░░░░░▒▒░▒▓▓▓▓▓▓▓██▓▓▓██▓▓█▓███▓▓▒░░░░░░███▓▓█▓░░▒▒▒▒▒▒▓▓██▓▓█▓▓█▓▓▓██▓▓▓▓▓▓▓▒░░▓░░░░░░░//
//░░░░░▒░░░░▒▒▓▓██████████████▓▓▓▒░░░░░░░▓██▓██▓░░░░▒▒▒▒▒▓▓███████████████▓▓▒▒░░░░▒░░░░░░//
//░░░░▓▒▓▒▒▒▒▒▓█▓▓▒▒▒▒▒▒▓▓████▓▓▒▒▒▒░░░░░▒▓███▓▒░░░░░▒▒▒▒▒▓▓████▓▓▒▒▒▒▒▒▓█▓▓▒▒▒▒▓▓▓░░░░░░//
//░░░▓▒░▒▓▓▓███░░░░░░░░░░░▒██▓▓▒▒▒▒▒▒░░░░░░▒▒▒░░░░░░▒▒▒▒▒▒▒▓███░░░░░░░░░░░▓██▓▓▓▒░░▓░░░░░//
//░░░█░▒▒▒▒▒▓█░░░░░░░░░░░░░▒█▓▓▓▒▒▒▒▓▓▓▒▒▒░░░░░░▒▒▓▓▓▓▒▒▒▓▓▓██░░░░░░░░░░░░░▓█▓▒▒▒▒▒▓▒░░░░//
//░░░█░▒▒▒▒▓█▓░░░▒░░░▒░░░░░▒█▓░▒▓▓▓▓▒▒░▒▓▓▒▒▒▒▒▓▓▒▒░▒▒▓▓▓▒▒▒██░░░░░░▒░░▒░░░░█▓▒▒▒▒░▓▒░░░░//
//░░░█░░░▒▓▓█▓░░▓▓▒▒▒░▒▒░░░▒█▓░▓▓▓▓▓▓▓▓▒▒▒▒▒▓▓▒▒▒▒▓▓▓▓▓██▓▒▒▓█░░░░▒▒░▒▒▓▓▒░░█▓▓▒▒░░▓▒░░░░//
//░░░▓▒▒▒░░▒▓▓▓░░░█▒▒▒▒▒▒░░▒█▒▓▒░░▒▓▓▓▓▓▓▓▓▒▒▒▒▓▓▓▓▓▓▓▓▒░▒▓▓▓█░░░▓▓▒▒▒▓▓░░▒█▓▓░░░▒▒█░░░░░//
//░░░░▓▓▒▒▓▓▓▒▓██▓▓▓▒▒▓▓▒░░▒█▒▒▒▒▓▓▒░▒▓▓▓▓▒▒▒▒▓▓▓▓▓▓▒░▒▓▓▒▒▒▓█░░░▓█▒▒▓▓▓██▓▓▒▓▓▓▒▒█▒░░░░░//
//░░░░░▓██▓▒░▓▒▒▓█▒▒▓███░░░▒█▒▒▒▒▒▒▒▓▒░▒▒▒▒▒▒▒▒▓▓▓░░▒▓▒▒▒▒▒▒▓█░░░▒███▓▒▓▓▒░▓▒▒▒▓██▓░░░░░░//
//░░░░░░▒▓█▓▓█▓▒▓█████▒░░░░▒█▒▒▒▒▒▒░░▓▒░▒▓▒▒▒▒▒▒▓░▒▓▒░▒▒▒▒▒▒▓█░░░░░▓█████▓▓██▓██▓▒░░░░░░░//
//░░░░░░░░░▒▒▓▓▓▓▒▒▒░░░░░░░▓█▓▒▒▒▒▒▒░▒▓▒▒▓▒▒▒▒▓▓▓░▒▓░▒▒▒▒▒▒▒▓█░░░░░░░░▒▒▓▓▓▓▒▒░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░░░░░░█▓▓▒▒▒▒▒▒▒░█▒░▒▒▒░▒▒▒▓░▒▓░▒▒▒▒▒▒▒▓█▓░░░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░░░░░▓█▓▓▒▒▒▒▒▒▒░█▒░▒▒░▒▒▒▒▒░▒▓░▒▒▒▒▒▒▓▓██░░░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░░░░▓██▓▓▓▒▒▒▒▒▒░█▒░▒░░░▒▒▒▒░▒▓░▒▒▒▒▒▒▓▓███░░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░▒▒████▓▓▓▓▒▒▒▒▒░█▒░▒░░░▒▒▒░░▒▓░▒▒▒▒▒▓▓▓▓███▓▒▒░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░▒█▓███▓▓▓▓▓▓▒▒▒▒░█▒░▒▒▒▒▒▒▒░▒▒▓▒▒▒▒▒▓▓▓▓▓▓███▓█░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░▒███▓██▓▓▓▓▓▒▒▒▒█▒▒▓▓▓▓▓▓▓█▒▓▓▒▒▒▓▓▓▓▓▓▓█▓██▓░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░░░░▓██▓▓▓▓▓▓▓▓▒▒▓▓▒▒░░░░░░▓▒▓▒▒▓▓▓▓▓▓▓▓██▓▒░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░░░░░░░▒▓██████▓▓▓▓▒▒░░░░░░▓▒█▒▓███████▓▒░░░░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▓▓██▓▒░░░░░░▓▓██▓▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒░░░░░░░░░//
//░░░▓▓██▓▓▓█░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒█▓▓▒░░░░░░░░//
//░░▒▓▓█░░░▓█░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒█▓█▓▒░░░░░░░░//
//░░░▓▓▓▓▒▒░▒▓▓▓▓░░░▓▓▓▓█▓▓▓▓▓▓▓▓▓▓▓▓▓▒▓▓▓▓▓▒▓▓▓▓▒▓▓▓▓▓▒▓▓▓▒▒▒█▓▓▓▓█▓▓▓▓░░░█▓███▒▓░░░░░░░//
//░░░░▒▓▓▓▓▓▓░▓█▓▓░▓▓▓▓▒░░▓▓▓▒▓▒░▓▓▓░▒▓▒█▓█▒▒▓▓▓█▓▓▒▒▓█▓▓▓█▓▓▓▓▓▓▓░▓█▓▓░░░▓█▓▓▓▓▓▒▒░░░░░░//
//░░▓▓░░░░▓▓█▓▓██▓▓▓█▓▓▒░░▓▓▓░░░░▓▓▓░░░░▓▓▓▓▓▓▓▓█▓▓░░░█▓▓▒█▓██▓▓▓▒░▒█▓▓░░▒█▓▓▒▒██▓▒▒░░░░░//
//░░▓▓▓▒▒▒▓██▓▓█▒▓▓█▒▓▓▓▒░▓▓▓░░░░▓▓▓░░░░▓▓▓░░▓▓▓██▓▒░░▓▓▒░█▓▒▒██▓▓░▒█▓▓▒▒█▓▓▓░░▓█▓▓▓▒▒░░░//
//░░░▒▒▓▓▓▓▒▒▓▓▓▓▒▓▒▒▓▓▓▓▓▓▓▓▓░░▒▓▓▓▓░░▓▓▓▓▒▒▓▓▓▒▒▓▓▓▓▒░▒▓▓▓▓░░▒▓▒▓▓▓▓▓▓▓▓▓▓▓▒▒▓▓▓▓▓▓▒░░░//
//░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░//
//░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░//
///////////////////////////////////////////////////////////////////////////////////////////


pragma solidity ^0.8.2;

import "./Ownable.sol";
import "./ERC721I.sol";
import "./MerkleProof.sol";
import "./IERC20.sol";

abstract contract Security {
    modifier onlySender() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }
}

contract SmithoniaWeapons is Ownable, ERC721I, Security {
    uint256 public maxSupply = 12300;
    bool public mintIsActive = false;
    bool public publicMintIsActive = false;
    address public magicAddress;
    uint256 public minimumAmount;
    string private _baseTokenURI;
    mapping(address => bool) private minter;
    bytes32 public merkleRoot;

    constructor() ERC721I("Smithonia Weapons", "SMITHWEP") {}

    function mintWl(bytes32[] calldata _merkleProof) external onlySender {
        require(mintIsActive, "Blacksmith sleeping");
        require(maxSupply > totalSupply, "Armory empty");
        require(minimumAmount > 0, "Magic amount is not set");
        uint256 magicBalance = IERC20(magicAddress).balanceOf(
            address(msg.sender)
        );
        require(magicBalance >= minimumAmount, "Not enough magic");
        require(!minter[msg.sender], "You have already minted");
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, leaf),
            "Not allowed to enter Smithonia"
        );
        minter[msg.sender] = true;
        uint256 id = totalSupply + 1;
        _mint(msg.sender, id);
        totalSupply++;
    }

    function publicMint() external onlySender {
        require(mintIsActive && publicMintIsActive, "Blacksmith sleeping");
        require(maxSupply > totalSupply, "Armory empty");
        require(!minter[msg.sender], "You have already minted");
        minter[msg.sender] = true;
        uint256 id = totalSupply + 1;
        _mint(msg.sender, id);
        totalSupply++;
    }

    /* ADMIN ESSENTIALS */

    function adminMint(uint256 quantity, address _target) external onlyOwner {
        require(maxSupply >= totalSupply + quantity, "Sold out");
        uint256 startId = totalSupply + 1;
        for (uint256 i = 0; i < quantity; i++) {
            _mint(_target, startId + i);
        }
        totalSupply += quantity;
    }

    function setBaseTokenURI(string memory baseURI) external onlyOwner {
        _setBaseTokenURI(baseURI);
    }

    function setMagicAddress(address _magicAddress) external onlyOwner {
        magicAddress = _magicAddress;
    }

    function setMinimumAmount(uint256 _minimumAmount) external onlyOwner {
        minimumAmount = _minimumAmount;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function toggleSale() public onlyOwner {
        mintIsActive = !mintIsActive;
    }

    function togglePublicSale() public onlyOwner {
        publicMintIsActive = !publicMintIsActive;
    }
    /* ADMIN ESSENTIALS */

    function hasMinted(address _addr) public view returns (bool) {
        return minter[_addr];
    }
}

