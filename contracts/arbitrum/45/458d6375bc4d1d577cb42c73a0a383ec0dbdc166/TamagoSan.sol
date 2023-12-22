// SPDX-License-Identifier: GPL-3.0
//author: Johnleouf21
pragma solidity 0.8.19;
import "./ERC721A.sol";
import "./ERC1155.sol";
import "./ERC1155Holder.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./AccessControl.sol";
import "./Traits.sol";
import "./Tsan.sol";

contract TamagoSan is ERC721A,Ownable,AccessControl,ERC1155Holder {

    using Strings for uint256;
    //Traits
    //add trait contract address
    Traits public traits = Traits(address(0x8e964564EfC66344C4fbCEf6Fa2219F77A1328F0));
    Tsan public tsan = Tsan(address(0xa247122da0a980dDf69b22f0f0C311cd2851a8F4));
    //Max Supply
    uint public maxSupply = 3333;
    uint  public MAX_PER_WALLET = 6;
    mapping(address => uint) private nftByWallet;
    //MINTER
    bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
    //
    //Stake mapping
    mapping(uint256=>uint256[]) stakedTraits;

    string baseURI =  "https://tamagosan-server.fra1.cdn.digitaloceanspaces.com/tamagosanMetadata/";

    
    constructor() ERC721A("Tamagosan NFT Gen1","TSN1") {
        //add signer public key (same as in django project)
        _setupRole(MINTER_ROLE, address(0x396E1d4d0Dc9e86Eff33f2cF9fe4F6F2f2FB1164));
    }


    function setTsanAddress(address _newTsanAddress) external onlyOwner {
    tsan = Tsan(_newTsanAddress);
    }

    function setTraitsAddress(address _newTraitsAddress) external onlyOwner {
    traits = Traits(_newTraitsAddress);
    }

    function randomMintPack(address to, uint256[] memory tokenIDs,bytes32 messageHash,bytes calldata signature, uint quantity, uint amountTsan, uint price) external payable {
        require(msg.value >= price, "Not enough Funds!");
        require(6 <= MAX_PER_WALLET, "Max 6 NFTs per wallet");
        verifyHash(to, tokenIDs, messageHash);
        verifySigner(messageHash,signature);
        for(uint i=0;i<tokenIDs.length;i++){
            traits.externalMint(msg.sender,tokenIDs[i]);
        }
        tsan.mint(msg.sender, amountTsan*10**12);
        if (quantity != 0) {
            require(totalSupply() + quantity <= maxSupply, "All the NFTs were sold");
            _safeMint(msg.sender, quantity);
            nftByWallet[msg.sender] += quantity;
        }
    }

    function givewayPack(address to, uint256[] memory tokenIDs,bytes32 messageHash,bytes calldata signature, uint quantity, uint amountTsan) external onlyOwner {
        verifyHash(to, tokenIDs, messageHash);
        verifySigner(messageHash,signature);
        for(uint i=0;i<tokenIDs.length;i++){
            traits.externalMint(to,tokenIDs[i]);
        }
        tsan.mint(to, amountTsan*10**12);
        if (quantity != 0) {
            require(totalSupply() + quantity <= maxSupply, "All the NFTs were sold");
            _safeMint(to, quantity);
        }
    }

    function mintShop(address to, uint256[] memory tokenIDs, uint prices, bytes32 messageHash, bytes calldata signature, uint256[] memory tokenSign) public payable {
        require(prices > 0, "Price is 0");
        require(IERC20(tsan).transferFrom(msg.sender,address(this), prices));
        verifyHash(to, tokenSign, messageHash);
        verifySigner(messageHash,signature);
        for(uint256 i = 0; i < tokenIDs.length; i++) {
            traits.externalMint(to,tokenIDs[i]);
        }
    }

    function mintShopEth(address to, uint256[] memory tokenIDs, uint prices, bytes32 messageHash, bytes calldata signature, uint256[] memory tokenSign) public payable {    
        require(prices > 0, "Price is 0");
        verifyHash(to, tokenSign, messageHash);
        verifySigner(messageHash,signature);
        for(uint256 i = 0; i < tokenIDs.length; i++) {
            traits.externalMint(to,tokenIDs[i]);
        }
    }

    function recycleParts(uint256[] memory tokenIDs, uint prices, bytes32 messageHash, bytes calldata signature, uint256[] memory tokenSign) public {
        require(prices > 0, "Price is 0");
        verifyHash(msg.sender, tokenSign, messageHash);
        verifySigner(messageHash,signature);
        for(uint256 i = 0; i < tokenIDs.length; i++) {
            uint tokenID = tokenIDs[i];
            require(traits.balanceOf(msg.sender, 0) >= 1, "You don't have Recycle Card");
            require(traits.balanceOf(msg.sender, tokenID) >= 1, "You don't have this part");
            traits.burn(msg.sender, 0, 1);
            traits.burn(msg.sender, tokenID, 1);
        }
        tsan.mint(msg.sender, prices);
    }

    function verifySigner(bytes32 messageHash,bytes calldata signature) internal view{
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v,r,s) = splitSignature(signature);
        address signer = ecrecover(messageHash, v, r, s);
        require(hasRole(MINTER_ROLE, signer),"Invalid Signer");
    }

    function splitSignature(bytes calldata signature) public pure returns(uint8 v,bytes32 r,bytes32 s){
        r = bytes32(signature[:32]);
        s = bytes32(signature[32:64]);
        v = uint8(bytes1(signature[64:]));
        return (v,r,s);
    }

    function verifyHash(address to,uint256[] memory tokenIDs,bytes32 messageHash) internal pure{
        bytes32 hash = generateHash(to,tokenIDs);
        require(hash == messageHash,"Invalid messageHash");
    }

    function generateHash(address to,uint256[] memory tokenIDs) internal pure returns(bytes32){
        bytes32 hash = keccak256(abi.encodePacked(to,tokenIDs));
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hash));
    }

    function ownerMint() public onlyOwner{
        _mint(msg.sender,totalSupply()+1);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721A, AccessControl,ERC1155Receiver) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function getOwnedNftIDs() public view returns(uint256[] memory){
        uint256 size = balanceOf(msg.sender);
        uint[] memory nfts = new uint[](size);
        uint index = 0;
        for(uint i=1;i<=totalSupply();i++){
            if(ownerOf(i)==msg.sender){
                nfts[index] = i;
                index+=1;
            }
        }   
        return nfts;
    }

    function getStakedTraits(uint256 tamagosanID) public view returns(uint256[] memory){
        return stakedTraits[tamagosanID];
    } 

    function upgradeStakedParts (address proprietary, uint256 tamagosanID, uint256[] calldata traitID, uint256[] calldata newTraitID, uint256[] memory newTokenIDs) public {
        require(ownerOf(tamagosanID)==msg.sender,"This NFT is not owned by you!");
        unstakeParts(traitID);
        upgrade(proprietary, traitID);
        stakeParts(newTraitID);
        stakedTraits[tamagosanID] = newTokenIDs;
    }

    //staking logic
    function editTamago(uint256 tamagosanID,uint256[] memory idsToStake,uint256[] memory idsToUnstake,uint256[] memory newTokenIDs) public {
        require(ownerOf(tamagosanID)==msg.sender,"This NFT is not owned by you!");
        if(idsToUnstake.length!=0){
            unstakeParts(idsToUnstake);
        }
        if(idsToStake.length > 0){
            stakeParts(idsToStake);
        }
        stakedTraits[tamagosanID] = newTokenIDs;
    }

    function unstakeParts(uint256[] memory unstakeIDs) internal{
        traits.editBatchTransfer(address(this),msg.sender,unstakeIDs);
    }

    function stakeParts(uint256[] memory stakeIDs) internal{
        traits.editBatchTransfer(msg.sender,address(this),stakeIDs);
    }

    function upgrade(address proprietary, uint[] memory tokenIDs) public {
        for (uint i = 0; i < tokenIDs.length; i++) {
            uint tokenID = tokenIDs[i];
            require(traits.balanceOf(proprietary, tokenID) >= 1, "You don't have this part");
            if (tokenID >= 1 && tokenID <= 1999) {
                require(traits.balanceOf(proprietary, 2000) > 0, "You don't have enough UPGRADE KIT Level 2");
                traits.burn(proprietary, 2000, 1);
            } else if (tokenID >= 2001 && tokenID <= 3999) {
                require(traits.balanceOf(proprietary, 4000) > 0, "You don't have enough UPGRADE KIT Level 3");
                traits.burn(proprietary, 4000, 1);
            } else if (tokenID >= 4001 && tokenID <= 5999) {
                require(traits.balanceOf(proprietary, 6000) > 0, "You don't have enough UPGRADE KIT Level 4");
                traits.burn(proprietary, 6000, 1);
            } else if (tokenID >= 6001 && tokenID <= 7999) {
                require(traits.balanceOf(proprietary, 8000) > 0, "You don't have enough UPGRADE KIT Level 5");
                traits.burn(proprietary, 8000, 1);
            } else if (tokenID >= 8001 && tokenID <= 9999) {
                require(traits.balanceOf(proprietary, 10000) > 0, "You don't have enough UPGRADE KIT Level 6");
                traits.burn(proprietary, 10000, 1);
            } else {
                revert("Invalid association of token ID and Upgrade Card");
            }
            traits.burn(proprietary, tokenID, 1);
            traits.externalMint(proprietary, (tokenID + 2000));
        }
    }

    function tokenURI(uint _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "URI query for nonexistent token");

        return string(abi.encodePacked(baseURI, _tokenId.toString(),".json"));
    }

    function withdraw(address _team) external onlyOwner {
        uint256 balance = address(this).balance; // get the balance of the smart contract
        payable(_team).transfer(balance);
    }    

    function getBalance() public view onlyOwner returns (uint256) {
        return address(this).balance;
    }
}
