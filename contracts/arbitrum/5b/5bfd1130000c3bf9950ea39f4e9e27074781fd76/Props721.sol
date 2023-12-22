// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ERC721.sol";
import "./SignatureChecker.sol";
import "./TransferHelper.sol";
import "./Configable.sol";

contract Props721 is ERC721, Configable {
    address public consumeToken;
    address public signer;
    string public baseURI;
    string public suffix;

    uint256 private _currentTokenId = 1;
    mapping(uint256 => bool) private _orders;

    event Create(address indexed user, uint256 orderId, uint256 propId, uint256 tokenId);
    event Destroy(address indexed user, uint256 tokenId);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string memory suffix_,
        address signer_,
        address consumeToken_
    ) ERC721(name_, symbol_) {
        require(signer_ != address(0), 'Zero address');
        owner = msg.sender;
        consumeToken = consumeToken_;
        signer = signer_;
        baseURI = baseURI_;
        suffix = suffix_;
    }

    function setBaseURI(string memory baseURI_, string memory suffix_) external onlyDev {
        baseURI = baseURI_;
        suffix = suffix_;
    }

    function setSigner(address signer_) external onlyDev {
        require(signer != signer_, 'There is no change');
        signer = signer_;
    }

    function setConsumeToken(address consumeToken_) external onlyDev {
        require(consumeToken != consumeToken_, "There is no change");
        consumeToken = consumeToken_;
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        require(IERC20(token).balanceOf(address(this))  >= amount, 'Insufficient balance');
        TransferHelper.safeTransfer(token, to, amount);
    }

    function mint(
        uint256 expiryTime,
        uint256 orderId,
        uint256 propId,
        uint256 consumeAmount,
        bytes memory signature
    ) external {
        require(expiryTime > block.timestamp, "Signature has expired");
        require(!_orders[orderId], "OrderId already exists");
        require(verifyMint(msg.sender, expiryTime, orderId, propId, consumeAmount, signature), "Invalid signature");
        
        _orders[orderId] = true;
        if (consumeAmount > 0) {
            TransferHelper.safeTransferFrom(consumeToken, msg.sender, address(this), consumeAmount);
        }
        uint256 tokenId = _currentTokenId;
        _mint(msg.sender, tokenId);
        _currentTokenId += 1;

        emit Create(msg.sender, orderId, propId, tokenId);
    }

    function burn(
        uint256 tokenId,
        uint256 consumeAmount,
        bytes memory signature
    ) external {
        require(verifyBurn(tokenId, consumeAmount, signature), "Invalid signature");
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner of tokenId");

        if (consumeAmount > 0) {
            TransferHelper.safeTransferFrom(consumeToken, msg.sender, address(this), consumeAmount);
        }

        _burn(tokenId);

        emit Destroy(msg.sender, tokenId);
    }

    function verifyMint(
        address account,
        uint256 expiryTime,
        uint256 orderId,
        uint256 propId,
        uint256 consumeAmount,
        bytes memory signature
    ) public view returns (bool) {
        bytes32 message = keccak256(abi.encodePacked(account, expiryTime, orderId, propId, consumeAmount, address(this)));
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        return SignatureChecker.isValidSignatureNow(signer, hash, signature);
    }

    function verifyBurn(
        uint256 tokenId,
        uint256 consumeAmount,
        bytes memory signature
    ) public view returns (bool) {
        bytes32 message = keccak256(abi.encodePacked(tokenId, consumeAmount, address(this)));
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        return SignatureChecker.isValidSignatureNow(signer, hash, signature);
    }

    function tokenURI(uint256 tokenId) public view override returns(string memory) {
        require(_exists(tokenId), "TokenId does not exist");
        return string(abi.encodePacked(baseURI, Strings.toString(tokenId), suffix));
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
