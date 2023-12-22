// File: contracts/lib/Auth.sol

pragma solidity ^0.8.0;
abstract contract Auth {
    address internal ownerr;
    mapping (address => bool) internal authorizations;

    constructor(address _owner) {
        ownerr = _owner;
        authorizations[_owner] = true;
    }

    /**
     * Function modifier to require caller to be contract owner
     */
    modifier onlyOwnerr() {
        require(isOwnerr(msg.sender), "!OWNER"); _;
    }

    /**
     * Function modifier to require caller to be authorized
     */
    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }

    /**
     * Authorize address. Owner only
     */
    function authorize(address adr) public onlyOwnerr {
        authorizations[adr] = true;
    }

    /**
     * Remove address' authorization. Owner only
     */
    function unauthorize(address adr) public onlyOwnerr {
        authorizations[adr] = false;
    }

    /**
     * Check if address is owner
     */
    function isOwnerr(address account) public view returns (bool) {
        return account == ownerr;
    }

    /**
     * Return address' authorization status
     */
    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    /**
     * Transfer ownership to new address. Caller must be owner. Leaves old owner authorized
     */
    function transferOwnershipp(address payable adr) public onlyOwnerr {
        ownerr = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    event OwnershipTransferred(address owner);
}

// File: contracts/lib/IERC20.sol

// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v4.4.0


// OpenZeppelin Contracts v4.4.0 (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// File: contracts/PaperHandsDistributor.sol

pragma solidity ^0.8.0;


contract PaperHandsDistributor is Auth {

    IERC20 PaperHands;

    uint256 public rewardAmount = 5000000000000000000000;

    uint256 public timeFrame = 86400;

    uint256 public totalShareHolders = 0;

    uint256 public minHoldingAmount = 0;

    struct shareHolderObject {
        address _userAddress;
        uint256 lastClaimTime;
        bool paused;
    }

    mapping(address => shareHolderObject) public shareHolder;

    constructor() Auth(msg.sender) {
        minHoldingAmount = 50000000 * 10**18;
    }

    function setPaperHands(address _tokenAddress) external authorized {
        PaperHands = IERC20(_tokenAddress);
        authorize(_tokenAddress);
    }

    function setRewardAmount(uint256 _rewardAmount) external authorized {
        rewardAmount = _rewardAmount;
    }

    function setMinHoldingAmount(uint256 _minAmount) external authorized {
        minHoldingAmount = _minAmount;
    }

    function getMinHoldingAmount() external view returns (uint256) {
        return minHoldingAmount;
    }

    function calculateReward() external view returns (uint256) {
        require(
            shareHolder[msg.sender]._userAddress != address(0),
            "Only shareholders"
        );

        uint256 currentTimestamp = block.timestamp;

        uint256 userLastClaimtime = shareHolder[msg.sender].lastClaimTime;

        uint256 rewardTimeFrame = currentTimestamp - userLastClaimtime;

        uint256 rewardPerSecond = rewardAmount / timeFrame;

        uint256 availableReward = rewardPerSecond * rewardTimeFrame;

        return availableReward;
    }

    function calculateUserReward(address _shareHolder)
        external
        view
        authorized
        returns (uint256)
    {
        require(
            shareHolder[_shareHolder]._userAddress != address(0),
            "Only shareholders"
        );

        uint256 currentTimestamp = block.timestamp;

        uint256 userLastClaimtime = shareHolder[msg.sender].lastClaimTime;

        uint256 rewardTimeFrame = currentTimestamp - userLastClaimtime;

        uint256 rewardPerSecond = rewardAmount / timeFrame;

        uint256 availableReward = rewardPerSecond * rewardTimeFrame;

        return availableReward;
    }

    function createShareHolder(address _shareHolder)
        external
        authorized
        returns (bool)
    {
        bool shareHolderStatus = shareHolder[_shareHolder].paused;

        address addr = shareHolder[_shareHolder]._userAddress;

        if (addr == _shareHolder) {
            if (shareHolderStatus == true) {
                shareHolder[_shareHolder].paused = false;
                shareHolder[_shareHolder].lastClaimTime = block.timestamp;
            }
        } else {
            shareHolder[_shareHolder] = shareHolderObject({
                _userAddress: _shareHolder,
                lastClaimTime: block.timestamp,
                paused: false
            });
        }

        totalShareHolders += 1;

        return true;
    }

    function removeShareHolder(address _shareHolder) external authorized {
        shareHolder[_shareHolder].paused = true;

        totalShareHolders -= 1;
    }

    function claimReward() external {
        address _shareHolder = msg.sender;

        uint256 currentTimestamp = block.timestamp;

        uint256 userLastClaimtime = shareHolder[_shareHolder].lastClaimTime;

        require(
            PaperHands.balanceOf(_shareHolder) >= minHoldingAmount,
            "Not qualified"
        );

        require(shareHolder[_shareHolder].paused != true, "Only shareholders");

        shareHolder[_shareHolder].lastClaimTime = block.timestamp;

        uint256 rewardTimeFrame = currentTimestamp - userLastClaimtime;

        uint256 rewardPerSecond = rewardAmount / timeFrame;

        uint256 availableReward = rewardPerSecond * rewardTimeFrame;

        PaperHands.transfer(msg.sender, availableReward);
    }

    function rescueToken(
        address _token,
        address _address,
        uint256 _amount
    ) external authorized {
        IERC20(_token).transfer(_address, _amount);
    }

    function rescueEth() external authorized {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }
}