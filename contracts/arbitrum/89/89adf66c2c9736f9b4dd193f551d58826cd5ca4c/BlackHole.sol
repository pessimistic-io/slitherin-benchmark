// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC721.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";

contract BlackHole is ERC721, AccessControl, Ownable {

/** Roles **/
    bytes32 public constant Admin = keccak256("Admin");

    bytes32 public constant Claimer = keccak256("Claimer");

    bytes32 public constant Requestor = keccak256("Requestor");

    function supportsInterface(bytes4 interfaceId) public view virtual override (ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    constructor () ERC721("BlackHole", "BlackHole") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

/** Metadata **/
    string public baseURI;

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "BlackHole: Token not exist.");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, Strings.toString(_tokenId), ".json")) : "";
    }

/** Community Deploy **/
    struct _community {
        string name;
        uint256 _type; /* 0=>Builder | 1=>KOL | 2=>DAO | 3=>Investors | Continues... */
        mapping (uint256 => string) communityId; /* 1=>Twitter | 2=>Discord | 3=>Youtube | 4=>Telegram | Continues... */
        uint256 level;
        uint256 deployTime;
    }

    mapping (uint256 => _community) public Community;

    function Deploy (uint256 _tokenId, string calldata _name, uint256 type_, uint256 batch, string calldata _communityId) public {
        require(ownerOf(_tokenId) == msg.sender || hasRole(Admin, msg.sender), "BlackHole: Only Owner or Admin can deploy.");
        Community[_tokenId].name = _name;
        Community[_tokenId]._type = type_;
        Community[_tokenId].communityId[batch] = _communityId;
    }

    /* Community Level */
    function getLevel (uint256 _tokenId) external view returns (uint256) {
        return Community[_tokenId].level;
    }

    function levelUp (uint256 _tokenId) external onlyRole(Claimer) {
        require(Community[_tokenId].level < 9, "BlackHole: You have reached the highest level.");
        Community[_tokenId].level++;
    }

/** POSW of Builders **/
    struct _POSW_Builder {
        uint256 POSW;
        mapping (uint256 => uint256) POSW_SocialPlatform;
    }

    mapping (uint256 => _POSW_Builder) private POSW_Builder;

    /* Global POSW */
    uint256 public POSW_Global;

    mapping (uint256 => uint256) public POSW_Global_SocialPlatform;

    function addPOSW_Builder (uint256 _tokenId, uint256 _POSW, uint256[] memory Id_SocialPlatform, uint256[] memory POSW_SocialPlatform) external onlyRole(Claimer) {
        require(_exists(_tokenId), "BlackHole: Token not exist.");
        POSW_Builder[_tokenId].POSW += _POSW;
        for (uint256 i=0; i<Id_SocialPlatform.length; i++) {
            POSW_Builder[_tokenId].POSW_SocialPlatform[Id_SocialPlatform[i]] += POSW_SocialPlatform[i];
            POSW_Global_SocialPlatform[Id_SocialPlatform[i]] += POSW_SocialPlatform[i];
        }
    }

    function getPOSW_Builder (uint256 _tokenId) external view onlyRole(Requestor) returns (uint256) {
        return POSW_Builder[_tokenId].POSW;
    }

    function getPOSW_Builder_Owner (uint256 _tokenId) external view returns (uint256) {
        require(ownerOf(_tokenId) == msg.sender, "BlackHole: You are not the owner of this SBT.");
        return POSW_Builder[_tokenId].POSW;
    }

    function getPOSW_Builder_SocialPlatform (uint256 _tokenId, uint256 _socialPlatform) external view onlyRole(Requestor) returns (uint256) {
        return POSW_Builder[_tokenId].POSW_SocialPlatform[_socialPlatform];
    }

    function getPOSW_Builder_SocialPlatform_Owner (uint256 _tokenId, uint256 _socialPlatform) external view returns (uint256) {
        require(ownerOf(_tokenId) == msg.sender, "BlackHole: You are not the owner of this SBT.");
        return POSW_Builder[_tokenId].POSW_SocialPlatform[_socialPlatform];
    }

/** Whitelist **/
    bytes32 public merkleRoot;

    function setWhitelist(bytes32 _merkleRoot) public onlyRole(Admin) {
        merkleRoot = _merkleRoot;
    }

    function verify(address sender, uint256 _airdrop, bytes32[] calldata merkleProof) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(sender, _airdrop));
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }

/** Mint **/
    uint256 public tokenId;

    function totalSupply() external view returns (uint256) {
        return tokenId;
    }

    function Price() public view returns (uint256 price) {
        if (tokenId >= 50) {
            price = 0.01 ether + (tokenId - 50) * 0.01 ether;
        } else {
            price = 0 ether;
        }
    }

    mapping (address => uint256[]) public wallet_token;

    function getAllTokens(address owner) public view returns (uint256[] memory) {
        return wallet_token[owner];
    }

    mapping (address => bool) public alreadyMinted;

    function Mint (address owner, uint256 _airdrop, bytes32[] calldata merkleProof) public payable {
        require(!alreadyMinted[owner], "BlackHole: You have already minted your SBT.");
        require(verify(owner, _airdrop, merkleProof), "BlackHole: You are not in the whitelist.");
        if (_airdrop == 0) {
            require(msg.value >= Price(), "BlackHole: Not enough payment.");
        }
        tokenId++;
        _safeMint(owner, tokenId);
        Community[tokenId].deployTime = block.timestamp;
        wallet_token[owner].push(tokenId);
        alreadyMinted[owner] = true;
        emit mintRecord(owner, tokenId, block.timestamp);
    }

    function Airdrop (address owner) public onlyRole(Admin) {
        require(!alreadyMinted[owner], "BlackHole: You have already minted your SBT.");
        tokenId++;
        _safeMint(owner, tokenId);
        Community[tokenId].deployTime = block.timestamp;
        wallet_token[owner].push(tokenId);
        alreadyMinted[owner] = true;
        emit mintRecord(owner, tokenId, block.timestamp);
    }

    event mintRecord(address owner, uint256 tokenId, uint256 time);

/** Soul Bound Token **/
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize) internal virtual override {
        require(from == address(0) || to == address(0), "BlackHole: SBT can't be transfered.");
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

/** Undeploy By Burning **/
    function Burn(uint256 _tokenId) public {
        require(ownerOf(_tokenId) == msg.sender, "BlackHole: You are not the owner of this SBT.");
        _burn(_tokenId);
        delete wallet_token[msg.sender];
    }

/** Withdraw **/
    function Withdraw(address recipient) public onlyOwner {
        payable(recipient).transfer(address(this).balance);
    }
}
