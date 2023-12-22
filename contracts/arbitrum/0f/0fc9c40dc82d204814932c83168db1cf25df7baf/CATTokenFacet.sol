// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Context.sol";
import "./Ownable.sol";

import "./CATERC20.sol";
import "./LibDiamond.sol";
contract CATTokenFacet is Context {
	
	using SafeERC20 for IERC20;
	// --- all contract events listed here
	
	// when token deployed by hot wallet/admin this event will be emitted
	event TokenDeployed(
		address indexed owner,
		address indexed token,
		string name,
		string symbol,
		uint8 decimals,
		bytes32 salt
	);
	
	// when user initiate token deployment request this event will be emitted
	event InitiateTokenDeployment(
		address indexed owner,
		bytes params,
		uint256[] destinationChains,
		uint256[] gasValues,
		uint256 tokenMintingChain
	);
	
	
	// when user initiate bridge out request this event will be emitted
	event InitiatedBridgeOut(
		address indexed caller,
		address indexed token,
		uint256 amount,
		uint16 destinationChain,
		bytes32 recipient,
		uint256 nonce,
		uint256 gasValue,
		string trackId
	);
	// --- end of events
	/**
	 * @notice CATRelayer deploy token contract and this function will only be called by admin or hot wallet.
	 * @param name token name
	 * @param symbol token symbol
	 * @param decimals token decimals
	 * @param totalSupply token totalSupply
	 * @param salt token salt which is uniqued and store in relayer backend system.
	 * @param owner token owner
	 * @param chainIdForMinting chainId for minting tokens so supply should be minted on this chainId
	 */
	function deployToken(
		string calldata name,
		string calldata symbol,
		uint8 decimals,
		uint256 totalSupply,
		bytes32 salt,
		address owner,
		uint16 chainIdForMinting
	) external returns (address tokenAddress) {
		LibDiamond.enforceIsContractOwner();
		LibDiamond.DiamondStorage storage diamondStorage = LibDiamond.diamondStorage();
		address projectedTokenAddress = computeAddress(salt, name, symbol, decimals);
		require(!isContract(projectedTokenAddress) , "already address deployed");
		tokenAddress = address(new CATERC20{ salt: salt }(name, symbol, decimals));
		CATERC20(tokenAddress).initialize(diamondStorage.chainId, diamondStorage.wormhole, diamondStorage.finality , totalSupply);
		if (chainIdForMinting == diamondStorage.chainId){
			CATERC20(tokenAddress).mint(owner, totalSupply);
		}
		Ownable(tokenAddress).transferOwnership(_msgSender());
		emit TokenDeployed(owner, tokenAddress, name, symbol, decimals, salt);
	}
	
	/**
	 * @notice compute token address by salt before deployment.
	 * @param salt token salt which is uniqued and store in relayer backend system.
	 * @param name token name
	 * @param symbol token symbol
	 * @param decimals token decimals
	 */
	function computeAddress(bytes32 salt,             string calldata name,
		string calldata symbol,
		uint8 decimals) public view returns (address addr) {
		bytes memory byteCodeForContract = type(CATERC20).creationCode;
		
		bytes memory contractCode = abi.encodePacked(byteCodeForContract, abi.encode(name, symbol, decimals));
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
	 * @notice check if address is contract address or not.
	 * @param addr address
	 */
	function isContract(address addr) internal view returns (bool) {
		uint256 size;
		assembly { size := extcodesize(addr) }
		return size > 0;
	}
	
	/**
	* here user will initiate this function to deploy tokens on all selected chains.
	* @param params - params will be containing all the data required to deploy token on all selected chains.
    * @param destinationChains - array of destination chains
    * @param gasValues - array of gas values and this total sum should be equal to native value transfered to this function.
    */
	function initiateTokensDeployment(
		bytes calldata params,
		uint256[] calldata destinationChains,
		uint256[] calldata gasValues,
		uint256 tokenMintingChain
	) external payable {
		require(msg.value > 0, "invalid value for gas");
		require(destinationChains.length == gasValues.length, "invalid gas values and chains.");
		LibDiamond.DiamondStorage storage diamondStorage = LibDiamond.diamondStorage();
		
		
		diamondStorage.gasCollector.transfer(msg.value);
		
		emit InitiateTokenDeployment(
			_msgSender(), // this will be owner of token.
			params,
			destinationChains,
			gasValues,
			tokenMintingChain
		);
	} // end of initiate token deployment
	
	
	/**
	* @dev this function is allowed to be called by user to start relaying tokens on all selected chain.
 	*/
	function initiateBridgeOut(
		address tokenAddress,
		uint256 amount,
		uint16 recipientChain,
		bytes32 recipient,
		uint32 nonce,
		string calldata trackId
	) external payable {
		LibDiamond.DiamondStorage storage diamondStorage = LibDiamond.diamondStorage();
	
		require(msg.value > 0, "invalid value for gas");
		diamondStorage.gasCollector.transfer(msg.value);
		IERC20 erc20 = IERC20(tokenAddress);
		erc20.safeTransferFrom(_msgSender(), address(this), amount);
		if (erc20.allowance(address(this), tokenAddress) < amount) {
			erc20.approve(tokenAddress, (2**256 - 1));
		}
		

		// here we will call bridge out function of token contract.
		CATERC20(tokenAddress).bridgeOut(amount, recipientChain, recipient, nonce);
		
		emit InitiatedBridgeOut(
			_msgSender(),
			tokenAddress,
			amount,
			recipientChain,
			recipient,
			nonce,
			msg.value,
			trackId
		);
	}
} // end of contract
