// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./Strings.sol";
import "./ReentrancyGuard.sol";

contract Collection721 is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;
    using Counters for Counters.Counter;


    // Optional base URI
    string public baseURI = "";
    Counters.Counter tokenId_;
    address private _signer;
    address private _receiver;
    address private _canMintAirdrop;
    uint256 public pricePerNFT;
    uint256 public maxTotalSupply = 20000;
    uint256 public maxFreeMint = 4500;
    uint256 public maxDefaultMint = 15000;
    uint256 public maxAirdropMint = 500;
    uint256 public freeMintAmount = 0;
    uint256 public defaultMintAmount = 0;
    uint256 public airdropMintAmount = 0;
    
    

    mapping(bytes => bool) signatureInvalid;
    mapping(string => bool) internalIdInvalid;
    mapping(address => bool) public claimedFreeMint;

    event Mint(
        address indexed to_,
        uint256[] tokenIds,
        string internalId_
    );
    
    constructor(address signer, address receiver,string memory baseURI_, uint256 pricePerNFT_) ERC721("PEPE CIVIL WAR", "PEPE CIVIL WAR") {
        setURI(baseURI_);
        tokenId_._value = 0;
        _signer = signer;
        _receiver = receiver;
        pricePerNFT = pricePerNFT_;
        _canMintAirdrop = msg.sender;
    }

    function mint(uint256 _type,string memory internalId,bytes memory signature,uint256 amount) external payable nonReentrant {
        
        if(msg.sender != _canMintAirdrop){
            require(!internalIdInvalid[internalId],"PEPE CIVIL WAR: Invalid Internal ID");
            internalIdInvalid[internalId] = true;
            require(!signatureInvalid[signature] && verify(_type, internalId,msg.sender,amount, signature), "PEPE CIVIL WAR: Invalid Signature");
            signatureInvalid[signature] = true;
            require(amount == 1,"PEPE CIVIL WAR: Invalid Amount");
            if (_type == 0) {
                require(msg.value >= pricePerNFT,"PEPE CIVIL WAR: Value is invalid");
                require(defaultMintAmount < maxDefaultMint,"PEPE CIVIL WAR: Default mint request cannot exceed the limit");
                (bool sent, bytes memory data) = _receiver.call{value: msg.value}("");
                require(sent, "PEPE CIVIL WAR: Failed to send Ether");
                defaultMintAmount += 1;
            } else {
                require(!claimedFreeMint[msg.sender], "PEPE CIVIL WAR: Already Claim");
                require(freeMintAmount <= maxFreeMint,"PEPE CIVIL WAR: Free mint request cannot exceed the limit");
                freeMintAmount += 1;
                claimedFreeMint[msg.sender] = true;
            }
        } else {
            require(airdropMintAmount + amount <= maxAirdropMint,"PEPE CIVIL WAR: Airdrop mint request cannot exceed the limit");
            airdropMintAmount += amount;
        }
        uint256[] memory tokenIds = new uint256[](amount);
        for(uint256 i = 0; i < amount; i++) {
            tokenIds[i] = handleMint(msg.sender);
        }
        
        emit Mint(msg.sender, tokenIds, internalId);
    }

    function handleMint(address to_) internal returns(uint256){
        tokenId_.increment();
        uint256 _tokenId = tokenId_.current();
        require(_tokenId <= maxTotalSupply,"PEPE CIVIL WAR: Mint request cannot exceed the limit");
        _safeMint(to_, _tokenId);
        return _tokenId;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "PEPE CIVIL WAR: URI query for nonexistent token");
        
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    /**
     * @dev Return Message Hash
     * @param _type type of mint
     * @param _internalId internal ID
     * @param _to: address of user mint NFT
    */
    function getMessageHash(
        uint256 _type,
        string memory _internalId,
        address _to,
        uint256 _amount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_type,_internalId,_to, _amount));
    }

    /**
     * @dev Return ETH Signed Message Hash
     * @param _messageHash: Message Hash
    */
    function getEthSignedMessageHash(bytes32 _messageHash)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
            );
    }

    /**
     * @dev Return True/False
     * @param _type contract Address
     * @param _internalId internal ID
     * @param _to: address of user claim reward
     * @param signature: sign the message hash offchain
    */
    function verify(
        uint256 _type,
        string memory _internalId,
        address _to,
        uint256 _amount,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 messageHash = getMessageHash(_type,_internalId, _to, _amount);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        return recoverSigner(ethSignedMessageHash, signature) == _signer;
    }

    /**
     * @dev Return address of signer
     * @param _ethSignedMessageHash: ETH Signed Message Hash
     * @param _signature: sign the message hash offchain
    */
    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature)
        internal
        pure
        returns (address)
    {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    /**
     * @dev Return split Signature
     * @param sig: sign the message hash offchain
    */
    function splitSignature(bytes memory sig)
        internal
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
    }

    /**
     * @dev Set to new uri
     * @param uri_ new uri
     */
    function setURI(string memory uri_) public onlyOwner {
        baseURI = uri_;
    }

    function setSigner(address signer) external onlyOwner {
        _signer = signer;
    }

    function setMaxDeafaultMint(uint256 amount) external onlyOwner {
        require(amount >= defaultMintAmount,"Invalid amount");
        maxDefaultMint = amount;
    }
    function setMaxFreeMint(uint256 amount) external onlyOwner {
        require(amount >= freeMintAmount,"Invalid amount");
        maxFreeMint = amount;
    }
    function setMaxAirdropMint(uint256 amount) external onlyOwner {
        require(amount >= airdropMintAmount,"Invalid amount");
        maxAirdropMint = amount;
    }
    function setPricePerNFT(uint256 price) external onlyOwner {
        pricePerNFT = price;
    }
    function setReceiver(address newReceiver) external onlyOwner {
        _receiver = newReceiver;
    }
}
