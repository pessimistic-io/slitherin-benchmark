pragma solidity ^0.8.14;



library IsContract {
    function isContract(address _addr) internal view returns (bool) {
        bytes32 codehash;
        /* solium-disable-next-line */
        assembly { codehash := extcodehash(_addr) }
        return codehash != bytes32(0) && codehash != bytes32(0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470);
    }
}

// File: contracts/utils/SafeMath.sol

library SafeMath2 {
    function add(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 z = x + y;
        require(z >= x, "Add overflow");
        return z;
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256) {
        require(x >= y, "Sub underflow");
        return x - y;
    }

    function mult(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x == 0) {
            return 0;
        }

        uint256 z = x * y;
        require(z / x == y, "Mult overflow");
        return z;
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256) {
        require(y != 0, "Div by zero");
        return x / y;
    }

    function divRound(uint256 x, uint256 y) internal pure returns (uint256) {
        require(y != 0, "Div by zero");
        uint256 r = x / y;
        if (x % y != 0) {
            r = r + 1;
        }

        return r;
    }
}

// File: contracts/utils/Math.sol

library ExtendedMath2 {


    //return the smaller of the two inputs (a or b)
    function limitLessThan(uint a, uint b) internal pure returns (uint c) {

        if(a > b) return b;

        return a;

    }
}

// File: contracts/interfaces/IERC20.sol

interface IERC20 {
	function totalSupply() external view returns (uint256);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    function transfer(address _to, uint _value) external returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);
    function allowance(address _owner, address _spender) external view returns (uint256 remaining);
    function approve(address _spender, uint256 _value) external returns (bool success);
    function balanceOf(address _owner) external view returns (uint256 balance);
    
}



interface IERC721 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

//Recieve NFTs
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
//Main contract


interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC1155 is IERC165 {
    /**
     * @dev Emitted when `value` tokens of token type `id` are transferred from `from` to `to` by `operator`.
     */
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    /**
     * @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens, according to
     * `approved`.
     */
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    /**
     * @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
     *
     * If an {URI} event was emitted for `id`, the standard
     * https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
     * returned by {IERC1155MetadataURI-uri}.
     */
    event URI(string value, uint256 indexed id);

    /**
     * @dev Returns the amount of tokens of token type `id` owned by `account`.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {balanceOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);

    /**
     * @dev Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`,
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the caller.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
}
interface IERC1155Receiver is IERC165 {
    /**
     * @dev Handles the receipt of a single ERC1155 token type. This function is
     * called at the end of a `safeTransferFrom` after the balance has been updated.
     *
     * NOTE: To accept the transfer, this must return
     * `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     * (i.e. 0xf23a6e61, or its own function selector).
     *
     * @param operator The address which initiated the transfer (i.e. msg.sender)
     * @param from The address which previously owned the token
     * @param id The ID of the token being transferred
     * @param value The amount of tokens being transferred
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    /**
     * @dev Handles the receipt of a multiple ERC1155 token types. This function
     * is called at the end of a `safeBatchTransferFrom` after the balances have
     * been updated.
     *
     * NOTE: To accept the transfer(s), this must return
     * `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     * (i.e. 0xbc197c81, or its own function selector).
     *
     * @param operator The address which initiated the batch transfer (i.e. msg.sender)
     * @param from The address which previously owned the token
     * @param ids An array containing ids of each token being transferred (order and length must match values array)
     * @param values An array containing amounts of each token being transferred (order and length must match ids array)
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}

contract arbBTC421 is IERC20 {

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
    
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4){
	return IERC1155Receiver.onERC1155Received.selector;
	}	
    function onERC1155BatchReceived(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4){
	return IERC1155Receiver.onERC1155Received.selector;
	}
	
	
    uint public targetTime = 60 * 12;
    uint public multipler = 0;
// SUPPORTING CONTRACTS
//Events
    using SafeMath2 for uint256;
    using ExtendedMath2 for uint;
    event Mint(address indexed from, uint reward_amount, uint epochCount, bytes32 newChallengeNumber);
    event MegaMint(address indexed from, uint epochCount, bytes32 newChallengeNumber, uint NumberOfTokensMinted, uint256 TokenMultipler);

// Managment events
    uint256 override public totalSupply = 21000000000000000000000000;
    bytes32 private constant BALANCE_KEY = keccak256("balance");

    //BITCOIN INITALIZE Start
	
    uint _totalSupply = 21000000000000000000000000;
    uint public latestDifficultyPeriodStarted2 = block.timestamp; //BlockTime of last readjustment
    uint public epochCount = 0;//number of 'blocks' mined
	uint public latestreAdjustStarted = block.timestamp; // shorter blocktime of attempted readjustment
    uint public _BLOCKS_PER_READJUSTMENT = 1028; // should be 512 or 1028
    //a little number
    uint public  _MINIMUM_TARGET = 2**16;
    
    uint public  _MAXIMUM_TARGET = 2**234;
    uint public miningTarget = _MAXIMUM_TARGET.div(100);  //1000 million difficulty to start until i enable mining
    
    bytes32 public challengeNumber = blockhash(block.number - 1);   //generate a new one when a new reward is minted
    uint public rewardEra = 0;
    uint public maxSupplyForEra = (_totalSupply - _totalSupply.div( 2**(rewardEra + 1)));
    uint public reward_amount = 0;
    
    //Stuff for Functions
    uint public previousBlockTime  =  block.timestamp; // Previous Blocktime
    uint public Token2Per=           1000; //Amount of ETH distributed per mint somewhat
    uint public tokensMinted = 0;			//Tokens Minted only for Miners
    mapping(address => uint) balances;
    mapping(address => mapping(address => uint)) allowed;
    uint public slowBlocks = 0;
    uint public epochOld = 0;  //Epoch count at each readjustment 
    uint public give0x = 0;
    uint public give = 1;
    // metadata
    string public name = "Test Bitcoin";
    string public constant symbol = "Testing BTC";
    uint8 public constant decimals = 18;
	
    uint public latestDifficultyPeriodStarted = block.number;

	    constructor() {    
	    previousBlockTime = block.timestamp;
	    reward_amount = 20 * 10**uint(decimals);
    	    rewardEra = 0;
	    tokensMinted = 0;
	    epochCount = 0;
	    epochOld = 0;
	    multipler = address(this).balance / (1 * 10 ** 18); 	
	    Token2Per = (2** rewardEra) * address(this).balance / (250000 + 250000*(multipler)); //aimed to give about 400 days of reserves
    	    miningTarget = _MAXIMUM_TARGET.div(100); //5000000 = 31gh/s @ 7 min for FPGA mining
            latestDifficultyPeriodStarted2 = block.timestamp;
    	    _startNewMiningEpoch();
       	    slowBlocks = 0;
	}



	function ARewardSender() public {
		//runs every _BLOCKS_PER_READJUSTMENT / 8

		multipler = address(this).balance / (1 * 10 ** 18); 	
		Token2Per = (2** rewardEra) * address(this).balance / (250000 + 250000*(multipler)); //aimed to give about 400 days of reserves

		if(rewardEra < 8){
			
			targetTime = ((12 * 60) * 2**rewardEra);
		}else{
			reward_amount = ( 20 * 10**uint(decimals)).div( 2**(rewardEra - 7  ) );
		}
		
	}
	function timeFromLastSolve() public view returns (uint256 timez){
		timez = block.timestamp - previousBlockTime;
		return timez;
	}

	function rewardAtCurrentTime() public view returns (uint256 rewardz){
		uint256 x = (block.timestamp - previousBlockTime);
		rewardz = rewardAtTime(x);
		return rewardz;
	}
	
	function rewardAtTime(uint timeDifference) public view returns (uint256 rewardz){
		uint256 x = (timeDifference * 888) / targetTime;
		uint ratio = x * 100 / 888 ;
		uint totalOwed = 0;


		//best @ 3000 ratio totalOwed / 100000000 = 71.6
		if(ratio < 3000){
			totalOwed = (508606*(15*x**2)).div(888 ** 2)+ (9943920 * (x)).div(888);
		}else {
			totalOwed = (24*x*5086060).div(888)+3456750000;
		}

		rewardz = (reward_amount * totalOwed).div(100000000);

		return rewardz;
	}


	///
	// Managment
	///


	//comability function
	function mint(uint256 nonce, bytes32 challenge_digest) public returns (bool success) {
		mintTo(nonce, challenge_digest, msg.sender);
		return true;
	}
	

	function mintNFTGOBlocksUntil() public view returns (uint num) {
		return _BLOCKS_PER_READJUSTMENT/8 - slowBlocks % (_BLOCKS_PER_READJUSTMENT/8 );
	}
	
	function mintNFTGO() public view returns (uint num) {
		return slowBlocks % (_BLOCKS_PER_READJUSTMENT/8);
	}
	
	function mintNFT721(address nftaddy, uint nftNumber, uint256 nonce, bytes32 challenge_digest) public returns (bool success) {
		require(mintNFTGO() == 0, "Only mint on slowBlocks % _BLOCKS_PER_READJUSTMENT/8 == 0");
		mintTo(nonce, challenge_digest, msg.sender);
		IERC721(nftaddy).safeTransferFrom(address(this), msg.sender, nftNumber, "");
		return true;
	}

	function mintNFT1155(address nftaddy, uint nftNumber, uint256 nonce, bytes32 challenge_digest) public returns (bool success) {
		require(mintNFTGO() == 0, "Only mint on slowBlocks % _BLOCKS_PER_READJUSTMENT/8 == 0");
		mintTo(nonce, challenge_digest, msg.sender);
		IERC1155(nftaddy).safeTransferFrom(address(this), msg.sender, nftNumber, 1, "" );
		return true;
	}

	function mintTo(uint256 nonce, bytes32 challenge_digest, address mintToAddress) public returns (uint256 owed) {

		bytes32 digest =  keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce));

		//the challenge digest must match the expected
		require(digest == challenge_digest, "Old challenge_digest or wrong challenge_digest");

		//the digest must be smaller than the target
		require(uint256(digest) < miningTarget, "Digest must be smaller than miningTarget");
		_startNewMiningEpoch();

		require(block.timestamp > previousBlockTime, "No same second solves");
		
		//uint diff = block.timestamp - previousBlockTime;
		uint256 x = ((block.timestamp - previousBlockTime) * 888) / targetTime;
		uint ratio = x * 100 / 888 ;
		uint totalOwed = 0;
		
		
		if(ratio > 100){
			
			slowBlocks = slowBlocks.add(1);
			
		}
		
		//best @ 3000 ratio totalOwed / 100000000 = 71.6
		if(ratio < 3000){
			totalOwed = (508606*(15*x**2)).div(888 ** 2)+ (9943920 * (x)).div(888);
		}else {
			totalOwed = (24*x*5086060).div(888)+3456750000;
		}


		balances[mintToAddress] = balances[mintToAddress].add((reward_amount * totalOwed).div(100000000));
				
		tokensMinted = tokensMinted.add((reward_amount * totalOwed).div(100000000));
		previousBlockTime = block.timestamp;
		if(give0x > 0){
			if(ratio < 2000){
            			address payable to = payable(mintToAddress);
             			to.transfer((totalOwed * Token2Per * give0x).div(100000000));
				//IERC20(AddressZeroXBTC).transfer(mintTo, (totalOwed * Token2Per * give0xBTC).div(100000000 * 2));
			}else{
               			address payable to = payable(mintToAddress);
               			to.transfer((600 * Token2Per * give0x).div(10));
				//IERC20(AddressZeroXBTC).transfer(mintTo, (40 * Token2Per * give0xBTC).div(10 * 2));
			}
		}

		emit Mint(mintToAddress, (reward_amount * totalOwed).div(100000000), epochCount, challengeNumber );

		return totalOwed;

	}



	function mintToJustABAS(uint256 nonce, bytes32 challenge_digest, address mintToAddress) public returns (uint256 owed2) {

		bytes32 digest =  keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce));

		//the challenge digest must match the expected
		require(digest == challenge_digest, "Old challenge_digest or wrong challenge_digest");

		//the digest must be smaller than the target
		require(uint256(digest) < miningTarget, "Digest must be smaller than miningTarget");
		_startNewMiningEpoch();

		require(block.timestamp > previousBlockTime, "No same second solves");

		require(uint256(digest) < (miningTarget), "Digest must be smaller than miningTarget");
		
		//uint diff = block.timestamp - previousBlockTime;
		uint256 x = ((block.timestamp - previousBlockTime) * 888) / targetTime;
		uint ratio = x * 100 / 888 ;
		uint totalOwed = 0;
		
		
		if(ratio > 100){
			
			slowBlocks = slowBlocks.add(1);
			
		}
		
		//best @ 3000 ratio totalOwed / 100000000 = 71.6
		if(ratio < 3000){
			totalOwed = (508606*(15*x**2)).div(888 ** 2)+ (9943920 * (x)).div(888);
		}else {
			totalOwed = (24*x*5086060).div(888)+3456750000;
		}


		balances[mintToAddress] = balances[mintToAddress].add((reward_amount * totalOwed).div(100000000));
		tokensMinted = tokensMinted.add((reward_amount * totalOwed).div(100000000));
		previousBlockTime = block.timestamp;
		

		emit Mint(msg.sender, (reward_amount * totalOwed).div(100000000), epochCount, challengeNumber );

		return totalOwed;

	}


	function mintTokensArrayTo(uint256 nonce, bytes32 challenge_digest, address[] memory ExtraFunds, address[] memory MintTo) public returns (uint256 owed) {
		uint256 totalOd = mintTo(nonce,challenge_digest, MintTo[0]);
		require(totalOd > 0, "mint issue");

		require(MintTo.length == ExtraFunds.length + 1,"MintTo has to have an extra address compared to ExtraFunds");
		uint xy=0;
		for(xy = 0; xy< ExtraFunds.length; xy++)
		{
			if(epochCount % (2**(xy+1)) != 0){
				break;
			}
			for(uint y=xy+1; y< ExtraFunds.length; y++){
				require(ExtraFunds[y] != ExtraFunds[xy], "No printing The same tokens");
			}
		}
		
		uint256 totalOwed = 0;
		uint256 TotalOwned = 0;
		for(uint x=0; x<xy; x++)
		{
			//epoch count must evenly dividable by 2^n in order to get extra mints. 
			//ex. epoch 2 = 1 extramint, epoch 4 = 2 extra, epoch 8 = 3 extra mints, ..., epoch 32 = 5 extra mints w/ a divRound for the 5th mint(allows small balance token minting aka NFTs)
			if(epochCount % (2**(x+1)) == 0){
				TotalOwned = IERC20(ExtraFunds[x]).balanceOf(address(this));
				if(TotalOwned != 0){
					if( x % 3 == 0 && x != 0 && totalOd > 17600000 && give == 2){
						totalOwed = ( (2** rewardEra) *TotalOwned * totalOd).divRound(100000000 * 20000);
						
					}else{
						totalOwed = ( (2** rewardEra) * TotalOwned * totalOd).div(100000000 * 20000);
					}
				}
			    IERC20(ExtraFunds[x]).transfer(MintTo[x+1], totalOwed);
			}
		}
        	
        	
		emit MegaMint(msg.sender, epochCount, challengeNumber, xy, totalOd );

		return totalOd;

    }

	function mintTokensSameAddress(uint256 nonce, bytes32 challenge_digest, address[] memory ExtraFunds, address MintTo) public returns (bool success) {
		address[] memory dd = new address[](ExtraFunds.length + 1); 

		for(uint x=0; x< (ExtraFunds.length + 1); x++)
		{
			dd[x] = MintTo;
		}
		
		mintTokensArrayTo(nonce, challenge_digest, ExtraFunds, dd);

		return true;
	}


	function empty_mintTo(uint256 nonce, bytes32 challenge_digest, address[] memory ExtraFunds, address[] memory MintTo) public returns (uint256 owed) {
		bytes32 digest =  keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce));

		//the challenge digest must match the expected
		require(digest == challenge_digest, "Old challenge_digest or wrong challenge_digest");

		//the digest must be smaller than the target
		require(uint256(digest) < miningTarget, "Digest must be smaller than miningTarget");
		_startNewMiningEpoch();

		require(block.timestamp > previousBlockTime, "No same second solves");
		require(MintTo.length == ExtraFunds.length,"MintTo has to have same number of addressses as ExtraFunds");
		
		require(uint256(digest) < (miningTarget), "Digest must be smaller than miningTarget");
		uint xy=0;
		for(xy = 0; xy< ExtraFunds.length; xy++)
		{
			if(epochCount % (2**(xy+1)) != 0){
				break;
			}
			for(uint y=xy+1; y< ExtraFunds.length; y++){
				require(ExtraFunds[y] != ExtraFunds[xy], "No printing The same tokens");
			}
		}

		uint256 x = ((block.timestamp - previousBlockTime) * 888) / targetTime;
		uint ratio = x * 100 / 888 ;
		uint totalOwed = 0;

		
		if(ratio > 100){
			
			slowBlocks = slowBlocks.add(1);
			
		}
		if(ratio < 3000){
			totalOwed = (508606*(15*x**2)).div(888 ** 2)+ (9943920 * (x)).div(888);
		}else {
			totalOwed = (24*x*5086060).div(888)+3456750000;
			
		}

		uint256 TotalOwned;
		for(uint z=0; z<xy; z++)
		{
			//epoch count must evenly dividable by 2^n in order to get extra mints. 
			//ex. epoch 2 = 1 extramint, epoch 4 = 2 extra, epoch 8 = 3 extra mints, epoch 16 = 4 extra mints w/ a divRound for the 4th mint(allows small balance token minting aka NFTs)
			if(epochCount % (2**(x+1)) == 0){
				TotalOwned = IERC20(ExtraFunds[x]).balanceOf(address(this));
				if(TotalOwned != 0){
					if( x % 3 == 0 && x != 0 && totalOwed > 17600000 && give == 2 ){
						totalOwed = ( (2** rewardEra) * TotalOwned * totalOwed).divRound(100000000 * 20000);
					}else{
						totalOwed = ( (2** rewardEra) * TotalOwned * totalOwed).div(100000000 * 20000 );
				    }
			    	IERC20(ExtraFunds[x]).transfer(MintTo[x], totalOwed);

           		}
       		}
		}
		previousBlockTime = block.timestamp;
		return totalOwed;   
	}

	function mintToFREE(bool nonce, bool challenge_digest, address mintToAddress) public returns (uint256 owed) {

		_startNewMiningEpoch();

		require(block.timestamp > previousBlockTime, "No same second solves");
		
		//uint diff = block.timestamp - previousBlockTime;
		uint256 x = ((block.timestamp - previousBlockTime) * 888) / targetTime;
		uint ratio = x * 100 / 888 ;
		uint totalOwed = 0;
		
		
		if(ratio > 100){
			
			slowBlocks = slowBlocks.add(1);
			
		}
		
		//best @ 3000 ratio totalOwed / 100000000 = 71.6
		if(ratio < 3000){
			totalOwed = (508606*(15*x**2)).div(888 ** 2)+ (9943920 * (x)).div(888);
		}else {
			totalOwed = (24*x*5086060).div(888)+3456750000;
		}


		balances[mintToAddress] = balances[mintToAddress].add((reward_amount * totalOwed).div(100000000));
				
		tokensMinted = tokensMinted.add((reward_amount * totalOwed).div(100000000));
		previousBlockTime = block.timestamp;
		if(give0x > 0){
			if(ratio < 2000){
            			address payable to = payable(mintToAddress);
             			to.transfer((totalOwed * Token2Per * give0x).div(100000000));
				//IERC20(AddressZeroXBTC).transfer(mintTo, (totalOwed * Token2Per * give0xBTC).div(100000000 * 2));
			}else{
               			address payable to = payable(mintToAddress);
               			to.transfer((600 * Token2Per * give0x).div(10));
				//IERC20(AddressZeroXBTC).transfer(mintTo, (40 * Token2Per * give0xBTC).div(10 * 2));
			}
		}

		emit Mint(mintToAddress, (reward_amount * totalOwed).div(100000000), epochCount, challengeNumber );

		return totalOwed;

	}




	function _startNewMiningEpoch() internal {


		//if max supply for the era will be exceeded next reward round then enter the new era before that happens
		//59 is the final reward era, almost all tokens minted
		if( tokensMinted.add(reward_amount) > maxSupplyForEra && rewardEra < 15)
		{
			rewardEra = rewardEra + 1;
			maxSupplyForEra = _totalSupply - _totalSupply.div( 2**(rewardEra + 1));
			if(rewardEra < 8){
				targetTime = ((12 * 60) * 2**rewardEra);
				if(rewardEra < 6){
					if(_BLOCKS_PER_READJUSTMENT <= 16){
						_BLOCKS_PER_READJUSTMENT = 8;
					}else{
						_BLOCKS_PER_READJUSTMENT = _BLOCKS_PER_READJUSTMENT / 2;
					}
				}
			}else{
				reward_amount = ( 20 * 10**uint(decimals)).div( 2**(rewardEra - 7  ) );
			}
		}

		//set the next minted supply at which the era will change
		// total supply of MINED tokens is 21000000000000000000000000  because of 18 decimal places

		epochCount = epochCount.add(1);

		//every so often, readjust difficulty. Dont readjust when deploying
		if((epochCount - epochOld) % (_BLOCKS_PER_READJUSTMENT / 8) == 0)
		{
            ARewardSender();
			maxSupplyForEra = _totalSupply - _totalSupply.div( 2**(rewardEra + 1));

			uint256 blktimestamp = block.timestamp;
			uint TimeSinceLastDifficultyPeriod2 = blktimestamp - latestreAdjustStarted;
			uint adjusDiffTargetTime = targetTime *  (_BLOCKS_PER_READJUSTMENT / 8) ; 
			latestreAdjustStarted = block.timestamp;

			if( TimeSinceLastDifficultyPeriod2 > adjusDiffTargetTime || (epochCount - epochOld) % _BLOCKS_PER_READJUSTMENT == 0)
			{
				_reAdjustDifficulty();
			}
		}

		challengeNumber = blockhash(block.number - 1);
        
 }

	function inflation () public view returns (uint amt, uint z2, uint z3, uint z4){
		if(epochCount - epochOld == 0){
			return (0, 0, 0, 0);
		}
		uint256 blktimestamp = block.timestamp;
		uint TimeSinceLastDifficultyPeriod2 = blktimestamp - latestreAdjustStarted;

        
		uint timePerEpoch = TimeSinceLastDifficultyPeriod2 / blocksFromReadjust(); 
		uint rewardsz = rewardAtTime(timePerEpoch);
		uint year = 365 * 24 * 60 * 60;
		uint diff = year / timePerEpoch;
		amt = rewardsz * diff;
		return (amt, diff, rewardsz, timePerEpoch);
	}
	

	function blocksFromReadjust() public view returns (uint256 blockz){
		blockz = (epochCount - epochOld);
		return blockz;
	}
	
	function blocksToReadjust() public view returns (uint amtz){
		if((epochCount - epochOld) == 0){
			if(give == 1){
				return (_BLOCKS_PER_READJUSTMENT);
			}else{
				return (_BLOCKS_PER_READJUSTMENT / 8);
			}
		}
		uint256 blktimestamp = block.timestamp;
		uint TimeSinceLastDifficultyPeriod2 = blktimestamp - latestreAdjustStarted;
		uint adjusDiffTargetTime = targetTime * ((epochCount - epochOld) % (_BLOCKS_PER_READJUSTMENT/8)); 

		if( TimeSinceLastDifficultyPeriod2 > adjusDiffTargetTime)
		{
				amtz = _BLOCKS_PER_READJUSTMENT/8 - ((epochCount - epochOld) % (_BLOCKS_PER_READJUSTMENT/8));
				return (amtz);
		}else{
			    amtz = _BLOCKS_PER_READJUSTMENT - ((epochCount - epochOld) % _BLOCKS_PER_READJUSTMENT);
			    return (amtz);
		}
	
	}
	
	
	function _reAdjustDifficulty() internal {
		uint256 blktimestamp = block.timestamp;
		uint TimeSinceLastDifficultyPeriod2 = blktimestamp - latestDifficultyPeriodStarted2;
		uint epochTotal = epochCount - epochOld;
		uint adjusDiffTargetTime = targetTime *  epochTotal; 
		epochOld = epochCount;

		//if there were less eth blocks passed in time than expected
		if( TimeSinceLastDifficultyPeriod2 < adjusDiffTargetTime )
		{
			uint excess_block_pct = (adjusDiffTargetTime.mult(100)).div( TimeSinceLastDifficultyPeriod2 );
			give = 1;
			uint excess_block_pct_extra = excess_block_pct.sub(100).limitLessThan(1000);
			//make it harder 
			miningTarget = miningTarget.sub(miningTarget.div(2000).mult(excess_block_pct_extra));   //by up to 50 %
		}else{
			uint shortage_block_pct = (TimeSinceLastDifficultyPeriod2.mult(100)).div( adjusDiffTargetTime );
			give = 2;
			uint shortage_block_pct_extra = shortage_block_pct.sub(100).limitLessThan(1000); //always between 0 and 1000
			//make it easier
			miningTarget = miningTarget.add(miningTarget.div(500).mult(shortage_block_pct_extra));   //by up to 200 %
		}

		latestDifficultyPeriodStarted2 = blktimestamp;
		latestDifficultyPeriodStarted = block.number;
		if(miningTarget < _MINIMUM_TARGET) //very difficult
		{
			miningTarget = _MINIMUM_TARGET;
		}
		if(miningTarget > _MAXIMUM_TARGET) //very easy
		{
			miningTarget = _MAXIMUM_TARGET;
		}
		
	}



	//help debug mining software
	function checkMintSolution(uint256 nonce, bytes32 challenge_digest, bytes32 challenge_number, uint testTarget) public view returns (bool success) {
		bytes32 digest = bytes32(keccak256(abi.encodePacked(challenge_number,msg.sender,nonce)));
		if(uint256(digest) > testTarget) revert();

		return (digest == challenge_digest);
	}


	//this is a recent ethereum block hash, used to prevent pre-mining future blocks
	function getChallengeNumber() public view returns (bytes32) {

		return challengeNumber;

	}


	//the number of zeroes the digest of the PoW solution requires.  Auto adjusts
	function getMiningDifficulty() public view returns (uint) {
			return _MAXIMUM_TARGET.div(miningTarget);
	}


	function getMiningTarget() public view returns (uint) {
			return (miningTarget);
	}


	function getMiningMinted() public view returns (uint) {
		return tokensMinted;
	}

	//21m coins total
	//reward begins at 150 and is cut in half every reward era (as tokens are mined)
	function getMiningReward() public view returns (uint) {
		//once we get half way thru the coins, only get 25 per block
		//every reward era, the reward amount halves.

		if(rewardEra < 8){
			return ( 20 * 10**uint(decimals));
		}else{
			return ( 20 * 10**uint(decimals)).div( 2**(rewardEra - 7  ) );
		}
		}


	function getEpoch() public view returns (uint) {

		return epochCount ;

	}


	//help debug mining software
	function getMintDigest(uint256 nonce, bytes32 challenge_digest, bytes32 challenge_number) public view returns (bytes32 digest) {

		digest =  keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce));

		return digest;

	}


		// ------------------------------------------------------------------------

		// Get the token balance for account `tokenOwner`

		// ------------------------------------------------------------------------

	function balanceOf(address tokenOwner) public override view returns (uint balance) {

		return balances[tokenOwner];

	}


		// ------------------------------------------------------------------------

		// Transfer the balance from token owner's account to `to` account

		// - Owner's account must have sufficient balance to transfer

		// - 0 value transfers are allowed

		// ------------------------------------------------------------------------


	function transfer(address to, uint tokens) public override returns (bool success) {

		balances[msg.sender] = balances[msg.sender].sub(tokens);
		balances[to] = balances[to].add(tokens);

		emit Transfer(msg.sender, to, tokens);

		return true;

	}


		// ------------------------------------------------------------------------

		// Token owner can approve for `spender` to transferFrom(...) `tokens`

		// from the token owner's account

		//

		// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md

		// recommends that there are no checks for the approval double-spend attack

		// as this should be implemented in user interfaces

		// ------------------------------------------------------------------------


	function approve(address spender, uint tokens) public override returns (bool success) {

		allowed[msg.sender][spender] = tokens;

		emit Approval(msg.sender, spender, tokens);

		return true;

	}


		// ------------------------------------------------------------------------

		// Transfer `tokens` from the `from` account to the `to` account

		//

		// The calling account must already have sufficient tokens approve(...)-d

		// for spending from the `from` account and

		// - From account must have sufficient balance to transfer

		// - Spender must have sufficient allowance to transfer

		// - 0 value transfers are allowed

		// ------------------------------------------------------------------------


	function transferFrom(address from, address to, uint tokens) public override returns (bool success) {

		balances[from] = balances[from].sub(tokens);
		allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);
		balances[to] = balances[to].add(tokens);

		emit Transfer(from, to, tokens);

		return true;

	}


		// ------------------------------------------------------------------------

		// Returns the amount of tokens approved by the owner that can be

		// transferred to the spender's account

		// ------------------------------------------------------------------------


	function allowance(address tokenOwner, address spender) public override view returns (uint remaining) {

		return allowed[tokenOwner][spender];

	}




	  //Allow ETH to enter
	receive() external payable {

	}


	fallback() external payable {

	}
}