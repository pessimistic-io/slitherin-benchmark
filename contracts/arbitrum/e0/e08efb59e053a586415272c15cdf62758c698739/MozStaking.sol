// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./SafeERC20.sol";

import "./IMozToken.sol";
import "./IXMozToken.sol";
/*
 * MozStaking is Mozaic's escrowed governance token obtainable by converting MOZ to it
 * It's non-transferable, except from/to whitelisted addresses
 * It can be converted back to MOZ through a vesting process
 * This contract is made to receive MozStaking deposits from users in order to allocate them to Usages (plugins) contracts
 */
contract MozStaking is Ownable {
    
    using Address for address;
    using SafeERC20 for IMozToken;
    using SafeERC20 for IXMozToken;

    struct RedeemInfo {
        uint256 mozAmount; // MOZ amount to receive when vesting has ended
        uint256 xMozAmount; // xMOZ amount to redeem
        uint256 endTime;
    }

    IMozToken public mozaicToken; // MOZ token to convert to/from
    IXMozToken public xMozToken;
    address public daoTreasury;
    bool private flag;
    uint256 public constant MAX_FIXED_RATIO = 100; // 100%

    // Redeeming min/max settings
    uint256 public minRedeemRatio = 50; // 1:0.5
    uint256 public mediumRedeemRatio = 75; // 1:0.75
    uint256 public maxRedeemRatio = 100; // 1:1
    uint256 public minRedeemDuration = 15 days; // 1,296,000s
    uint256 public mediumRedeemDuration = 30 days; // 2,592,000s
    uint256 public maxRedeemDuration = 45 days; // 3,888,000s

    mapping(address => uint256) public xMozRedeemingBalances; // User's xMOZ balances
    mapping(address => RedeemInfo[]) public userRedeems; // User's redeeming instances

    constructor(
        address daoTreasury_
    ) {
        require(daoTreasury_ != address(0x0), "Invalid addr");
        daoTreasury = daoTreasury_;
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event Convert(address indexed from, address to, uint256 amount);
    event UpdateRedeemSettings(uint256 minRedeemRatio, uint256 mediumRedeemRatio, uint256 maxRedeemRatio, uint256 minRedeemDuration, uint256 mediumRedeemDuration, uint256 maxRedeemDuration);
    event Redeem(address indexed userAddress, uint256 xMozAmount, uint256 mozAmount, uint256 duration);
    event FinalizeRedeem(address indexed userAddress, uint256 xMozAmount, uint256 mozAmount);
    event CancelRedeem(address indexed userAddress, uint256 xMozAmount);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /**
    * @dev Check if a redeem entry exists
    */
    modifier validateRedeem(address userAddress, uint256 redeemIndex) {
        require(redeemIndex < userRedeems[userAddress].length, "validateRedeem: redeem entry does not exist");
        _;
    }

    /**************************************************/
    /******************* INITIALIZE* ******************/
    /**************************************************/

    /**
    * @dev Initialize contract parameters
     */
    function initialize(address mozaicToken_, address xMoztoken_) external {
        require(mozaicToken_ != address(0x0) || xMoztoken_ != address(0x0), "Invalid addr");
        require(!flag, "Already initialized");
        mozaicToken = IMozToken(mozaicToken_);
        xMozToken = IXMozToken(xMoztoken_);
        flag = true;
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /**
    * @dev Returns user's xMOZ balances
    */
    function getRedeemingXMozBalance(address userAddress) external view returns (uint256 redeemingAmount) {
        uint256 balance = xMozRedeemingBalances[userAddress];
        return balance;
    }

    /**
    * @dev returns redeemable MOZ for "amount" of xMOZ vested for "duration" seconds
    */
    function getMozByVestingDuration(uint256 amount, uint256 duration) public view returns (uint256) {
        uint256 ratio;
        
        if(duration < minRedeemDuration) {
            return 0;
        }
        else if(duration >= minRedeemDuration && duration < mediumRedeemDuration) {
            ratio = minRedeemRatio + (mediumRedeemRatio - minRedeemRatio) * (duration - minRedeemDuration) / (mediumRedeemDuration - minRedeemDuration);
        }
        else if(duration >= mediumRedeemDuration && duration < maxRedeemDuration) {
            ratio = mediumRedeemRatio + (maxRedeemRatio - mediumRedeemRatio) * (duration - mediumRedeemDuration) / (maxRedeemDuration - mediumRedeemDuration);
        }
        // capped to maxRedeemDuration
        else {
            ratio = maxRedeemRatio;
        }

        return amount * ratio / MAX_FIXED_RATIO;
    }

    /**
    * @dev returns quantity of "userAddress" pending redeems
    */
    function getUserRedeemsLength(address userAddress) external view returns (uint256) {
        return userRedeems[userAddress].length;
    }

    /**
    * @dev returns "userAddress" info for a pending redeem identified by "redeemIndex"
    */
    function getUserRedeem(address userAddress, uint256 redeemIndex) external view validateRedeem(userAddress, redeemIndex) returns (uint256 mozAmount, uint256 xMozAmount, uint256 endTime) {
        RedeemInfo storage _redeem = userRedeems[userAddress][redeemIndex];
        return (_redeem.mozAmount, _redeem.xMozAmount, _redeem.endTime);
    }

    /*******************************************************/
    /****************** OWNABLE FUNCTIONS ******************/
    /*******************************************************/

    /**
    * @dev Updates all redeem ratios and durations
    *
    * Must only be called by owner
    */
    function updateRedeemSettings(uint256 minRedeemRatio_, uint256 mediumRedeemRatio_, uint256 maxRedeemRatio_, uint256 minRedeemDuration_, uint256 mediumRedeemDuration_, uint256 maxRedeemDuration_) external onlyOwner {
        require(minRedeemRatio_ <= mediumRedeemRatio_ && mediumRedeemRatio_ <= maxRedeemRatio_, "updateRedeemSettings: wrong ratio values");
        require(minRedeemDuration_ < mediumRedeemDuration_ && mediumRedeemDuration_ < maxRedeemDuration_, "updateRedeemSettings: wrong duration values");
        // should never exceed 100%
        require(maxRedeemRatio_ <= MAX_FIXED_RATIO, "updateRedeemSettings: wrong ratio values");

        minRedeemRatio = minRedeemRatio_;
        mediumRedeemRatio = mediumRedeemRatio_;
        maxRedeemRatio = maxRedeemRatio_;
        minRedeemDuration = minRedeemDuration_;
        mediumRedeemDuration = mediumRedeemDuration_;
        maxRedeemDuration = maxRedeemDuration_;

        emit UpdateRedeemSettings(minRedeemRatio_, mediumRedeemRatio_, maxRedeemRatio_, minRedeemDuration_, mediumRedeemDuration_, maxRedeemDuration_);
    }


    /*****************************************************************/
    /******************  EXTERNAL PUBLIC FUNCTIONS  ******************/
    /*****************************************************************/

    /**
    * @dev Convert caller's "amount" of MOZ to xMOZ
    */
    function convert(uint256 amount) external  {
        _convert(amount, msg.sender);
    }

    /**
    * @dev Convert caller's "amount" of MOZ to xMOZ to "to" address
    */
    function convertTo(uint256 amount, address to) external  {
        require(address(msg.sender).isContract(), "convertTo: not allowed");
        _convert(amount, to);
    }

    /**
    * @dev Initiates redeem process (xMOZ to MOZ)
    *
    */
    function redeem(uint256 xMozAmount, uint256 duration) external  {
        require(xMozAmount > 0, "redeem: xMozAmount cannot be zero");
        require(duration >= minRedeemDuration, "redeem: Invalid duration");
        uint256 mozAmount = getMozByVestingDuration(xMozAmount, duration);
        xMozToken.burn(xMozAmount, msg.sender);
        uint256 redeemingAmount = xMozRedeemingBalances[msg.sender];
        // get corresponding MOZ amount
        if (mozAmount > 0) {
             emit Redeem(msg.sender, xMozAmount, mozAmount, duration);
            // add to total
            xMozRedeemingBalances[msg.sender] = redeemingAmount + xMozAmount;
            // add redeeming entry
            userRedeems[msg.sender].push(RedeemInfo(mozAmount, xMozAmount, _currentBlockTimestamp() + duration));
        }
    }

    /**
    * @dev Finalizes redeem process when vesting duration has been reached
    *
    * Can only be called by the redeem entry owner
    */
    function finalizeRedeem(uint256 redeemIndex) external  validateRedeem(msg.sender, redeemIndex) {
        uint256 redeemingAmount = xMozRedeemingBalances[msg.sender];
        RedeemInfo storage _redeem = userRedeems[msg.sender][redeemIndex];
        require(_currentBlockTimestamp() >= _redeem.endTime, "finalizeRedeem: vesting duration has not ended yet");

        // remove from SBT total
        xMozRedeemingBalances[msg.sender] = redeemingAmount - _redeem.xMozAmount;
        _finalizeRedeem(msg.sender, _redeem.xMozAmount, _redeem.mozAmount);
        // remove redeem entry
        _deleteRedeemEntry(redeemIndex);
    }

    
    /**
    * @dev Cancels an ongoing redeem entry
    *
    * Can only be called by its owner
    */
    function cancelRedeem(uint256 redeemIndex) external  validateRedeem(msg.sender, redeemIndex) {
        uint256 redeemingAmount = xMozRedeemingBalances[msg.sender];
        RedeemInfo storage _redeem = userRedeems[msg.sender][redeemIndex];

        // make redeeming xMOZ available again
        xMozRedeemingBalances[msg.sender] = redeemingAmount - _redeem.xMozAmount;
        xMozToken.mint(_redeem.xMozAmount, msg.sender);

        emit CancelRedeem(msg.sender, _redeem.xMozAmount);

        // remove redeem entry
        _deleteRedeemEntry(redeemIndex);
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    /**
    * @dev Convert caller's "amount" of MOZ into xMOZ to "to"
    */
    function _convert(uint256 amount, address to) internal {
        require(amount != 0, "convert: amount cannot be null");

        mozaicToken.burn(amount, msg.sender);
        // mint new xMOZ
        xMozToken.mint(amount, to);

        emit Convert(msg.sender, to, amount);
    }

    /**
    * @dev Finalizes the redeeming process for "userAddress" by transferring him "mozAmount" and removing "xMozAmount" from supply
    *
    * Any vesting check should be ran before calling this
    * MOZ excess is automatically burnt
    */
    function _finalizeRedeem(address userAddress, uint256 xMozAmount, uint256 mozAmount) internal {
        // sends due MOZ tokens 
        uint256 mozExcess = xMozAmount - mozAmount;
        // sends due Moz tokens
        mozaicToken.mint(mozAmount, userAddress);
        // burns Moz excess if any
        if(mozExcess > 0) {
            mozaicToken.mint(mozExcess, daoTreasury);
        }
        emit FinalizeRedeem(userAddress, xMozAmount, mozAmount);
    }


    function _deleteRedeemEntry(uint256 index) internal {
        userRedeems[msg.sender][index] = userRedeems[msg.sender][userRedeems[msg.sender].length - 1];
        userRedeems[msg.sender].pop();
    }

    /**
    * @dev Utility function to get the current block timestamp
    */
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        /* solhint-disable not-rely-on-time */
        return block.timestamp;
    }
}
