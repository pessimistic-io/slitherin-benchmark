// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./Context.sol";
import "./Counters.sol";
import "./IERC20.sol";
import "./CloudTrait.sol";

contract NimbusCloud is Context, Ownable, ERC721Enumerable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdTracker;
    CloudTrait public trait;
    mapping(CloudTrait.Level=>uint256) public cloudCounters;

    string public _baseTokenURI;

    uint256 public maxMintPerTx = 20;
    uint256 public startTrade;

    address public nodeManager;

    modifier onlyNodeManager {
        require(nodeManager == _msgSender(), "FBD: Caller is not the node manager.");
        _;
    }

    event NewCloud(address receiver, CloudTrait.Level indexed level);

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI,
        CloudTrait _trait
    ) ERC721(name, symbol) {
        _baseTokenURI = baseTokenURI;
        _tokenIdTracker.increment();
        startTrade = block.timestamp + 3 days;
        trait = _trait;
    }
    
    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        return trait.tokenURI(_tokenId);
    }

    /**
     * @dev allow node manager contract to mint _mintAmount token
     * @param _mintAmount is the total amount user want to mint
     */
    function mint(uint256 _mintAmount, address _receiver, CloudTrait.Level _level) external onlyNodeManager {
        require(
            _mintAmount <= maxMintPerTx,
            "Exceeds max amount per transaction allowed"
        );
        for (uint256 i = 1; i <= _mintAmount; i++) {
            trait.addTrait(_tokenIdTracker.current(), _level, _receiver);
            _mint(_receiver, _tokenIdTracker.current());
            emit NewCloud(_receiver, _level);
            cloudCounters[_level] += 1;
            _tokenIdTracker.increment();
        }
    }

    function claim(uint256 _tokenId, address _sender) external onlyNodeManager {
        require(ownerOf(_tokenId) == _sender, "FBD: Sender is not the owner of given token.");
        trait.setLastClaim(_tokenId);
    }

    function setBaseTokenURI(string memory uri) external onlyOwner {
        _baseTokenURI = uri;
        trait.setURI(uri);
    }

    function setNodeManager(address _nodeManager) external onlyOwner {
        nodeManager = _nodeManager;
    }

    /**
     * @dev return a list of the nft's held by the address provided
     * @param _owner address provided of a holder
     */
    function walletOfOwner(
        address _owner
    ) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        require(block.timestamp > startTrade, "FBD: Token transfer not allowed yet.");
        super._transfer(from, to, tokenId);
    }
}

