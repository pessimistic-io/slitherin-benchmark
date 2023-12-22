// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721URIStorage.sol";
import "./ERC6551Registry.sol";
import "./SocialPetAccount.sol";
import "./IERC6551Account.sol";

contract SocialPetExtended is ERC721URIStorage {
    address private _owner;
    uint256 private _tokenId;
    uint256 private _maxSupply = 10000;
    ERC6551Registry private _registry;
    SocialPetAccount private _accountContract;
    uint256 public cost = 0.01 ether;
    uint256 public totalSupply;
    uint256 public foundFee = 2000;
    address public foundAddress;
    address public projectAddress;
    
    mapping(uint256 => address) public accountAddress;

    event minted(uint256);

    constructor() ERC721("OG GM.Pets", "OG GM.Pets") {
        _owner = msg.sender;
        _registry = new ERC6551Registry();
    }

    function mint(address to, string memory tokenURI) external payable {
        require(msg.value == cost, "Insufficient Funds Sent");
        require(_maxSupply > totalSupply, "");
        _tokenId += 1;
        _accountContract = new SocialPetAccount();
        uint256 salt = generateRandomSalt();
        bytes memory emptyBytes = "";
        accountAddress[_tokenId] = _registry.createAccount(address(_accountContract), block.chainid, address(this), _tokenId, salt, emptyBytes);
        address expectedAddress = _registry.account(address(_accountContract), block.chainid, address(this), _tokenId, salt);
        require( accountAddress[_tokenId] == expectedAddress, "wrong addresses");
        _safeMint(to, _tokenId);
        _setTokenURI(_tokenId, tokenURI);
        uint256 fee = msg.value * foundFee / 10000;
        transferETH(payable( foundAddress), fee);
        transferETH(payable( projectAddress), msg.value - fee);
        totalSupply += 1;
        emit minted(_tokenId);
    }

    function nextId() internal view returns(uint256) {
        return _tokenId;
    }

    function getNextId() external view returns(uint256) {
        return nextId();
    }

    function generateRandomSalt() internal view returns (uint256) {
        bytes32 hash = keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce()));
        return uint256(hash);
    }

    function owner() external view returns(address) {
        return _owner;
    }

    function nonce() internal pure returns (uint256) {
        return 1;
    }

    function transferETH(address payable to, uint amount) internal {
        (bool success, ) = to.call{value: amount}("");
        require(success, "Failed to send Ether");
    }

     function tokensOfOwner(address account) external view  returns (uint256[] memory) {
        uint256 tokenIdsIdx;
        uint256 tokenIdsLength = balanceOf(account);
        uint256[] memory tokenIds = new uint256[](tokenIdsLength);
        uint256 supply = nextId();
        for (uint256 i = 1; i <= supply; i++) {
            if (ownerOf(i) == account) {
                tokenIds[tokenIdsIdx] = i;
                tokenIdsIdx++;
            }
        }

        return tokenIds;
    }

    function setCost(uint256 newCost) external returns(bool) {
        require(msg.sender == _owner);
        cost = newCost;
        return true;
    }

    function setFoundFee(uint256 newFee) external returns(bool) {
        require(msg.sender == _owner);
        foundFee = newFee;
        return true;
    }

    function setFoundAddress(address newFoundAddress) external returns(bool) {
        require(msg.sender == _owner);
        foundAddress = newFoundAddress;
        return true;
    }

    function setProjectAddress(address newProjectAddress) external returns(bool) {
        require(msg.sender == _owner);
        projectAddress = newProjectAddress;
        return true;
    }

    function setOwner(address newOwner) external returns(bool) {
        require(msg.sender == _owner);
        _owner = newOwner;
        return true;
    }
}
