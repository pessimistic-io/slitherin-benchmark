// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721A, IERC721A} from "./ERC721A.sol";
import {Ownable} from "./Ownable.sol";
import "./MerkleProof.sol";

/**
 * @title  Shikaku nft
 * @notice This contract is configured to use the DefaultOperatorFilterer, which automatically registers the
 *         token and subscribes it to OpenSea's curated filters.
 *         Adding the onlyAllowedOperator modifier to the transferFrom and both safeTransferFrom methods ensures that
 *         the msg.sender (operator) is allowed by the OperatorFilterRegistry.
 */
contract Shikaku is
    ERC721A,
    Ownable
{
    //variables and consts
    bytes32 public merkleRoot;

    bool public publicMintEnabled = false;
    bool public WhitelistMintEnabled = false;

    mapping(address => bool) public whitelistClaimed;
    mapping(address => bool) public publicClaimed;

    string public uriSuffix = ".json";
    string public baseURI = "";

    uint256 public shikaku_supply = 3333;
    uint256 public whitelistSupply = 2500;
    uint256 public price = 0.0 ether;
    uint256 public shikaku_per_tx = 1;

    constructor() ERC721A("Shikaku NFT", "SHKK") {
        _mint(msg.sender, 1);
    }

    function mintPublic(uint256 quantity) public payable{
        uint256 supply = totalSupply();
        require (publicMintEnabled, "Public mint not live yet");
        require(!publicClaimed[msg.sender], "Address already minted");
        require(quantity + supply <= 3250, "Public Supply exceeded");
        require(msg.value >= quantity * price, "Invalid input price");
        _mint(msg.sender, quantity);
        publicClaimed[msg.sender] = true;
        delete supply;
    }
    

    function mintWhitelist(uint256 quantity, bytes32[] calldata merkleProof) public payable{
        uint256 mintedShikaku = totalSupply();
        require(WhitelistMintEnabled, "The mint isn't open yet");
        require(quantity == 1, "Invalid quantity to mint");
        require(mintedShikaku + quantity <= shikaku_supply, "Cannot mint over supply");
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(!whitelistClaimed[msg.sender], "Whitelist already minted");
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Invalid proof!" );
        _mint(msg.sender, quantity);
        whitelistClaimed[msg.sender] = true;
        delete mintedShikaku;
    }

    function setPublicMintEnabled(bool enabled) public onlyOwner{
        publicMintEnabled = enabled;
    }

    function setWhitelistMintEnabled(bool enabled) public onlyOwner{
        WhitelistMintEnabled = enabled;
    }

     /**
     * @notice Change merkle root hash
     */
    function setMerkleRoot(bytes32 merkleRootHash) external onlyOwner{
        merkleRoot = merkleRootHash;
    }

    /**
     * @notice Verify merkle proof of the address
     */
    function verifyAddress(bytes32[] calldata merkleProof) private view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    }
}
