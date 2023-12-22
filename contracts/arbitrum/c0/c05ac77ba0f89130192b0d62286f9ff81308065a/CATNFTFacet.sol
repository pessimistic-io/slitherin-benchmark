// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ERC721.sol";
import "./Context.sol";
import "./Ownable.sol";

import "./CATERC721.sol";

import "./LibDiamond.sol";
contract CATNFTFacet is Context {
	
	// --- all contract events listed here
	event NFTDeployed(
		address indexed owner,
		address indexed token,
		string name,
		string symbol,
		bytes32 salt
	);
	event InitiateNFTDeployment(
		address indexed owner,
		bytes params,
		uint256[] destinationChains,
		uint256[] gasValues,
		uint256 tokenMintingChain
	);
	
	event InitiatedBridgeOutNFT(
		address indexed caller,
		address indexed token,
		uint256 tokenId,
		uint16 destinationChain,
		bytes32 recipient,
		uint256 nonce,
		uint256 gasValue,
		string trackId
	);
	

	// --- end of events
	
	
	/**
    * @notice CATRelayerNFT deploy nft contract
    */
	function deployNFT(
		string calldata name,
		string calldata symbol,
		uint256 totalSupply,
		bytes32 salt,
		address owner,
		string memory baseUri
	) external returns (address tokenAddress) {
		LibDiamond.enforceIsContractOwner();
		LibDiamond.DiamondStorage storage diamondStorage = LibDiamond.diamondStorage();
		address projectedTokenAddress = computeAddressNFT(salt, name, symbol);
		require(!isContract(projectedTokenAddress) , "already address deployed");
		tokenAddress = address(new CATERC721{ salt: salt }(name, symbol));
		CATERC721(tokenAddress).initialize(diamondStorage.chainId, diamondStorage.wormhole, diamondStorage.finality , totalSupply, baseUri);
		Ownable(tokenAddress).transferOwnership(_msgSender());
		emit NFTDeployed(owner, tokenAddress, name, symbol, salt);
	}
	
	
	function computeAddressNFT(bytes32 salt, string calldata name, string calldata symbol) public view returns (address addr) {
		bytes memory byteCodeForContract = type(CATERC721).creationCode;
		
		bytes memory contractCode = abi.encodePacked(byteCodeForContract, abi.encode(name, symbol));
		//create contract code hash
		bytes32 bytecodeHash = keccak256(contractCode);
		
		address deployer = address(this);
		assembly {
			let ptr := mload(0x40) // Get free memory pointer
		
		// |                   | ↓ ptr ...  ↓ ptr + 0x0B (start) ...  ↓ ptr + 0x20 ...  ↓ ptr + 0x40 ...   |
		// |-------------------|---------------------------------------------------------------------------|
		// | bytecodeHash      |                                                        CCCCCCCCCCCCC...CC |
		// | salt              |                                      BBBBBBBBBBBBB...BB                   |
		// | deployer          | 000000...0000AAAAAAAAAAAAAAAAAAA...AA                                     |
		// | 0xFF              |            FF                                                             |
		// |-------------------|---------------------------------------------------------------------------|
		// | memory            | 000000...00FFAAAAAAAAAAAAAAAAAAA...AABBBBBBBBBBBBB...BBCCCCCCCCCCCCC...CC |
		// | keccak(start, 85) |            ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑ |
			
			mstore(add(ptr, 0x40), bytecodeHash)
			mstore(add(ptr, 0x20), salt)
			mstore(ptr, deployer) // Right-aligned with 12 preceding garbage bytes
			let start := add(ptr, 0x0b) // The hashed data starts at the final garbage byte which we will set to 0xff
			mstore8(start, 0xff)
			addr := keccak256(start, 85)
		}
	}
	
	
	/**
	* here user will initiate this function to deploy tokens on all selected chains.
	* @param params - params will be containing all the data required to deploy token on all selected chains.
    * @param destinationChains - array of destination chains
    * @param gasValues - array of gas values and this total sum should be equal to native value transfered to this function.
    */
	function initiateNFTDeployment(
		bytes calldata params,
		uint256[] calldata destinationChains,
		uint256[] calldata gasValues,
		uint256 tokenMintingChain
	) external payable {
		require(msg.value > 0, "invalid value for gas");
		require(destinationChains.length == gasValues.length, "invalid gas values and chains.");
		
		// (string memory name, string memory symbol, uint8 decimals, uint256 totalSupply) = abi.decode(
		//     params,
		//     (string, string, uint8, uint256)
		// );
		
		LibDiamond.DiamondStorage storage diamondStorage = LibDiamond.diamondStorage();
		
		diamondStorage.gasCollector.transfer(msg.value);
		
		emit InitiateNFTDeployment(
			_msgSender(), // this will be owner of token.
			params,
			destinationChains,
			gasValues,
			tokenMintingChain
		);
	}
	
	/**
	* @dev this function is allowed to be called by user to start relaying tokens on all selected chain.
     */
	function initiateBridgeOutNFT(
		address tokenAddress,
		uint256 tokenId,
		uint16 recipientChain,
		bytes32 recipient,
		uint32 nonce,
		string calldata trackId
	) external payable {
		require(msg.value > 0, "invalid value for gas");
		LibDiamond.DiamondStorage storage diamondStorage = LibDiamond.diamondStorage();
		
		diamondStorage.gasCollector.transfer(msg.value);
		ERC721 nexaErc721 = ERC721(tokenAddress);
		nexaErc721.transferFrom(_msgSender(), address(this), tokenId);

		nexaErc721.setApprovalForAll(diamondStorage.wormhole, true);
		CATERC721(tokenAddress).bridgeOut(tokenId, recipientChain, recipient, nonce);
		
		emit InitiatedBridgeOutNFT(
			_msgSender(),
			tokenAddress,
			tokenId,
			recipientChain,
			recipient,
			nonce,
			msg.value,
			trackId
		);
	}
	
	/**
	 * @notice check if address is contract address or not.
	 * @param addr address
	 */
	function isContract(address addr) internal view returns (bool) {
		uint256 size;
		assembly { size := extcodesize(addr) }
		return size > 0;
	}
	

} // end of contract

