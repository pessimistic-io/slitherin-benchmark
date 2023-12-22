// Sources flattened with hardhat v2.12.6 https://hardhat.org

// File @openzeppelin/contracts/utils/Context.sol@v4.8.1


// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}


// File @openzeppelin/contracts/access/Ownable.sol@v4.8.1


// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


// File contracts/ffrebuildnftrewards.sol

pragma solidity ^0.8.9;

// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC721/IERC721.sol)

pragma solidity ^0.8.0;


interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function totalToken() external view returns (uint256);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library Address {
    function isContract(address account) internal view returns (bool) {
        uint256 size; assembly {
            size := extcodesize(account)
        } return size > 0;
    }
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }
    function functionCall(address target,bytes memory data,string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }
    function functionCallWithValue(address target,bytes memory data,uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }
    function functionCallWithValue(address target,bytes memory data,uint256 value,string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }
    function functionStaticCall(address target,bytes memory data,string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }
    function functionDelegateCall(address target,bytes memory data,string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }
    function verifyCallResult(bool success,bytes memory returndata,string memory errorMessage) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

library SafeERC20 {
    using Address for address;
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }
    function safeIncreaseAllowance(IERC20 token,address spender,uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }
    function safeDecreaseAllowance(IERC20 token,address spender,uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }
    function _callOptionalReturn(IERC20 token, bytes memory data) private {   
        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}



// Structures
struct User {
    uint256 lastClaimDate;
    uint256 claimCount;
}

struct Rewards {
    uint256 index;
    uint256 rewardDate;
    uint256 rewardAmount;
    uint256 rewardTotal;
}

contract fireRebuildNFTreward is Ownable {
	using SafeERC20 for IERC20;

	// https://www.unixtimestamp.com/
	uint256 constant launch = 1668277613; 						// Need to change
	uint256 constant year = 31556926;							// 365.24 days
    uint256 constant halfYear = 15778463;                       // Year / 2
	uint256 constant quarter = 7889229;							// 1 Month x 3
	uint256 constant payout = 1000000000000000000;	 			// 1 StableCoin
    uint256 counter = 0;
    uint256 token_decimals = 1000000000000;

	mapping (address => User) public UsersKey;
    
    Rewards[] public rewardsData;

	IERC721 public fireRebuildNFT;
	IERC20 public StableCoin;

    address initialStableCoin = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

	constructor() {
		fireRebuildNFT = IERC721(0xB7D93F7150C21D9aDaA3Ba95f095d057E6B61f40);
		StableCoin = IERC20(initialStableCoin);
	}


	function claimRewards() public payable returns (uint256 rewards) {
		User storage user = UsersKey[msg.sender];

		uint256 rewardsAvailable = rewardsCalculation(msg.sender);

		require (rewardsAvailable > 0, "No rewards to claim!");

        uint256 numOfNFT = nftCount(msg.sender);
        uint256 userLastClaimDate = user.lastClaimDate;

        for (uint256 i = 0; i < rewardsData.length; i++) {
            if (rewardsData[i].rewardDate > userLastClaimDate) {
                rewardsData[i].rewardTotal = rewardsData[i].rewardTotal - (numOfNFT * rewardsData[i].rewardAmount);
            }
        }        

		user.lastClaimDate = block.timestamp;

		StableCoin.safeTransfer(msg.sender, rewardsAvailable);

		return (rewardsAvailable);
	}


	function rewardsCalculation(address userAddress) public view returns (uint256 availableRewards) {
		User storage user = UsersKey[userAddress];
		
        uint256 userLastClaimDate = user.lastClaimDate;

        uint256 numOfNFT = nftCount(userAddress);

        uint256 currentTime = block.timestamp;

        availableRewards = 0;

        for (uint256 i = 0; i < rewardsData.length; i++) {
            if (rewardsData[i].rewardDate < currentTime) {
                if (rewardsData[i].rewardDate > userLastClaimDate) {
                    availableRewards += rewardsData[i].rewardAmount;
                }
            }
        }

        availableRewards = availableRewards * numOfNFT;
		return (availableRewards);
	}


	function nftCount(address userAddress) public view returns (uint256) {
		uint256 numOfNFT = fireRebuildNFT.balanceOf(userAddress);
		return numOfNFT;
	}

	function userInfo(address userAddress) public view returns (uint256, uint256) {
		User storage user = UsersKey[userAddress];

		uint256 currentTime = block.timestamp;

		return (user.lastClaimDate, currentTime);
	}

    function getRewardByTimestamp(uint256 rewardsIndex) public view returns (uint256 rewardDate, uint256 rewardsAmount, uint256 rewardTotal) {
        for (uint256 i = 0; i < rewardsData.length; i++) {
            if (rewardsData[i].index == rewardsIndex) {
                return (rewardsData[i].rewardDate, rewardsData[i].rewardAmount, rewardsData[i].rewardTotal);
            }
        }
    }

    function removeStableCoin(uint256 amtx) public onlyOwner {
        // Move funds from NFT wallet when changing stable coins
        StableCoin.safeTransfer(msg.sender, amtx);
    }

    function declareRewards(uint256 rewardsBlockTime, uint256 rewardsAmount) public onlyOwner {
        // Dev delcaring reward block time and reward amount
        counter += 1;
        uint256 rewardsAmountinSix = rewardsAmount / token_decimals;
        uint256 totalAmount = totalNFTMinted() * rewardsAmountinSix;

        rewardsData.push(Rewards(counter, rewardsBlockTime, rewardsAmountinSix, totalAmount));
    }

    function checkNumberOfRewardsDeclared() public view returns (uint256 numberOfDeclaration) {
        return rewardsData.length;
    }

    function setStableCoin(address stableCoin) public onlyOwner {
        // Ability to change stable coin
        StableCoin = IERC20(stableCoin);
    }

    function totalNFTMinted() public view returns (uint256) {
        return fireRebuildNFT.totalToken();
    }
}