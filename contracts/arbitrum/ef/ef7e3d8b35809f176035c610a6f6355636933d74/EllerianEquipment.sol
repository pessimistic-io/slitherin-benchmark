pragma solidity ^0.8.0;
//SPDX-License-Identifier: UNLICENSED

import "./ERC721.sol";
import "./ISignature.sol";

contract ITokenUriHelper {
  function GetTokenUri(uint256 _tokenId) external view returns (string memory) {}
  function GetClassName(uint256 _class) external view returns (string memory) {}
}

/** 
 * Tales of Elleria
*/
contract EllerianEquipment is ERC721 {

    uint256 private onchainSupply = 0;  // Keeps track of the current supply.
    uint256 private onchainCounter = 0; // Onchain minted tokens have even tokenIds.
    uint256 constant onchainStartTokenId = 2;
    uint256 constant offchainStartTokenId = 1;

    function totalSupply() public view returns (uint256) {
        return onchainSupply;
    }

    mapping (address => bool) private _approvedAddresses; // Reference to minting delegates.

    address private ownerAddress;             // The contract owner's address.   

    ITokenUriHelper uriAbi;                   // Reference to the tokenUri handler.
    ISignature signatureAbi;                  // Reference to the signature verifier.
    address private signerAddr;               // Reference to the signer.

    mapping (uint256 => bool) private isStaked;
    mapping (uint256 => bool) private isMinted;

    constructor() 
        ERC721("EllerianEquipment", "EllerianEquipment") {
            ownerAddress = msg.sender;
        }
        
        function _onlyOwner() private view {
            require(msg.sender == ownerAddress, "O");
        }

        modifier onlyOwner() {
            _onlyOwner();
            _;
    }
    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return uriAbi.GetTokenUri(tokenId);
    }

    function TransferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0));
        ownerAddress = _newOwner;
    }


    function SetApprovedAddress(address _address, bool _allowed) external onlyOwner {
        _approvedAddresses[_address] = _allowed;
    }  

    
    function SetAddresses(address _uriAddr, address _signatureAddr, address _signerAddr) external onlyOwner {
        signatureAbi = ISignature(_signatureAddr);
        uriAbi = ITokenUriHelper(_uriAddr);
        
        signerAddr = _signerAddr;
    } 

    /**
    * Allows the minting of NFTs from approved delegates.
    */
    function mintUsingToken(address _recipient, uint256 _amount, uint256 _equipId) public {
        require(_approvedAddresses[msg.sender], "Not Approved Mint Address");

        for (uint256 a = 0; a < _amount; a++) {
            uint256 tokenId = onchainStartTokenId + (onchainCounter++ * 2);
            mint(_recipient, tokenId, _equipId);
        }
    }

    function airdrop (address _recipient, uint256 _amount, uint256 _equipId) public onlyOwner {
        for (uint256 a = 0; a < _amount; a++) {
            uint256 tokenId = onchainStartTokenId + (onchainCounter++ * 2);
            mint(_recipient, tokenId, _equipId);
        }
    }

    /** 
     * Mints and tracks the supply. EquipId is only valid above 0.
     * 0 = Already exists.
     */
    function mint(address recipient, uint256 tokenId, uint256 equipId) internal {
        onchainSupply++;
        isMinted[tokenId] = true;

        _safeMint(recipient, tokenId);
        emit OnchainMint(recipient, tokenId, equipId);
    }
    
    function safeTransferFrom (address _from, address _to, uint256 _tokenId) public override {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    function safeTransferFrom (address _from, address _to, uint256 _tokenId, bytes memory _data) public override {
        require(_isApprovedOrOwner(_msgSender(), _tokenId), "SFF");
        _safeTransfer(_from, _to, _tokenId, _data);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal override {
        super._beforeTokenTransfer(_from, _to, _tokenId);

        if (_to != address(0)) {
            require(!isStaked[_tokenId], "Cannot Transfer Staked");
        }
    }
    
    function burn (uint256 _tokenId) public {
        require(_isApprovedOrOwner(_msgSender(), _tokenId), "Not Approved To Burn");
        _burn(_tokenId);
    }

    /* 
    * Allows the withdrawal of presale funds into the owner's wallet.
    * For fund allocation, refer to the whitepaper.
    */
    function withdraw() public onlyOwner {
        (bool success, ) = (msg.sender).call{value:address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    /**
    * Stakes your equipment into Elleria (on > off-chain)
    */
    function BridgeIntoGame(uint256[] memory _tokenIds) external {
        for (uint i = 0; i < _tokenIds.length; i++) {
            require(_isApprovedOrOwner(_msgSender(), _tokenIds[i]), "Not Approved To Unstake");
            isStaked[_tokenIds[i]] = true;
            
            emit Bridged(_tokenIds[i], true);
        }
    }

    /**
    * Unstakes your equipment from Elleria (off > on-chain)
    */
    function RetrieveFromGame(bytes memory _signature, uint256[] memory _tokenIds) external {
        uint256 tokenSum;
        for (uint i = 0; i < _tokenIds.length; i++) {
            // If equipment doesn't exist yet, mint it.
            if (!isMinted[_tokenIds[i]]) {
                mint(msg.sender, _tokenIds[i], 0);
            }

            require(_isApprovedOrOwner(msg.sender, _tokenIds[i]), "Not Approved To Unstake");
            tokenSum = _tokenIds[i] + tokenSum;
            isStaked[_tokenIds[i]] = false;

            emit Bridged(_tokenIds[i], false);
        }

        require(signatureAbi.verify(signerAddr, msg.sender, _tokenIds.length, "equipment withdrawal", tokenSum, _signature), "Invalid Unstake");
    }


    event OnchainMint(address indexed to, uint256 tokenId, uint256 equipmentId);
    event Bridged(uint256 tokenId, bool isStaked);
}
