// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Context.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import {IGeniVault} from "./IGeniVault.sol";
import {IBalanceHelper} from "./IBalanceHelper.sol";

contract LevelHelper is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    IERC20 public govToken;
    address public tokenFee;
    IGeniVault public botFactory;
    IBalanceHelper public balanceHelper;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    mapping(uint256 => uint256) public userLevel;
    mapping(uint256 => uint256) public traderLevel;
    mapping(uint256 => uint256) public refLevel;

    mapping(address => uint256) public userLevelFixed;
    mapping(address => uint256) public traderLevelFixed;
    mapping(address => uint256) public refLevelFixed;
    mapping(address => uint256) public userPackageTimes;
    mapping(address => uint256) public userPackageId;
    mapping(uint256 => uint256) public packageTimes;
    mapping(address => mapping(uint256 => uint256)) public packageTokenFeeAmount;

    mapping(uint256 => uint256) public refPackLevelFee;

    mapping(address => mapping(address => uint256)) public pendingRevenue;

    event BuyPackage(address indexed user, uint256 packageId, uint256 amount, address referrer, uint256 amountForReferrer);
    event RevenueClaim(address indexed claimer, uint256 amount);

    constructor(address _govToken, address _balanceHelper) {
        govToken = IERC20(_govToken);
        balanceHelper = IBalanceHelper(_balanceHelper);
        tokenFee = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

        packageTimes[1] = 30 days;
        packageTimes[2] = 60 days;
        packageTimes[3] = 90 days;
        packageTimes[4] = 180 days;
        packageTimes[5] = 365 days;

        packageTokenFeeAmount[tokenFee][1] = 100 * 10 ** 6;
        packageTokenFeeAmount[tokenFee][2] = 200 * 10 ** 6;
        packageTokenFeeAmount[tokenFee][3] = 300 * 10 ** 6;
        packageTokenFeeAmount[tokenFee][4] = 400 * 10 ** 6;
        packageTokenFeeAmount[tokenFee][5] = 500 * 10 ** 6;

        userLevel[1] = 10 * 10 ** 18;
        userLevel[2] = 100 * 10 ** 18;
        userLevel[3] = 1000 * 10 ** 18;
        userLevel[4] = 10000 * 10 ** 18;
        userLevel[5] = 100000 * 10 ** 18;

        traderLevel[1] = 1000 * 10 ** 18;
        traderLevel[2] = 10000 * 10 ** 18;
        traderLevel[3] = 100000 * 10 ** 18;
        traderLevel[4] = 10000000000000000000 * 10 ** 18;
        traderLevel[5] = 10000000000000000000 * 10 ** 18;

        refLevel[1] = 1000 * 10 ** 18;
        refLevel[2] = 2000 * 10 ** 18;
        refLevel[3] = 10000000000000000000 * 10 ** 18;
        refLevel[4] = 10000000000000000000 * 10 ** 18;
        refLevel[5] = 10000000000000000000 * 10 ** 18;

        refPackLevelFee[0] = 1000; // 10%
        refPackLevelFee[1] = 1500;
        refPackLevelFee[2] = 2000;
    }

    function setGovToken(address _govToken) external onlyOwner {
        govToken = IERC20(_govToken);
    }

    function setRefPackLevelFee(uint256 _level, uint256 _percent) external onlyOwner {
        refPackLevelFee[_level] = _percent;
    }

    function setGeniBotFactory(address _botFactory) external onlyOwner {
        botFactory = IGeniVault(_botFactory);
    }

    function setTokenFee(address _tokenFee) external onlyOwner {
        tokenFee = _tokenFee;
    }

    function setUserLevel(uint256 _level, uint256 _amount) external onlyOwner {
        userLevel[_level] = _amount;
    }

    function setTraderLevel(uint256 _level, uint256 _amount) external onlyOwner {
        traderLevel[_level] = _amount;
    }

    function setRefLevel(uint256 _level, uint256 _amount) external onlyOwner {
        refLevel[_level] = _amount;
    }

    function setUserLevelFixed(address _user, uint256 _level) external onlyOwner {
        userLevelFixed[_user] = _level;
    }

    function setTraderLevelFixed(address _trader, uint256 _level) external onlyOwner {
        traderLevelFixed[_trader] = _level;
    }

    function setRefLevelFixed(address _referrer, uint256 _level) external onlyOwner {
        refLevelFixed[_referrer] = _level;
    }
    
    function setPackageTimes(uint256 _packageId, uint256 _time) external onlyOwner {
        packageTimes[_packageId] = _time;
    }

    function setPackageTokenFeeAmount(address _tokenBuy, uint256 _packageId, uint256 _amount) external onlyOwner {
        packageTokenFeeAmount[_tokenBuy][_packageId] = _amount;
    }

    function buyPackage(address _tokenBuy, uint256 _packageId) external nonReentrant {
        require(userPackageTimes[msg.sender] <= block.timestamp, "You have package active now");
        uint256 amount = packageTokenFeeAmount[_tokenBuy][_packageId];
        require(amount > 0, "Wrong packageID");

        IERC20(_tokenBuy).safeTransferFrom(address(msg.sender), address(this), amount);

        address referrer = botFactory.getReferrer(msg.sender);
        uint256 amountForReferrer;

        if (referrer != address(0)) {
            uint256 feeRef = refPackLevelFee[getRefLevel(referrer)];
            amountForReferrer = feeRef * amount / BASIS_POINTS_DIVISOR;
            pendingRevenue[referrer][_tokenBuy] += amountForReferrer;
        }
        pendingRevenue[owner()][_tokenBuy] += amount - amountForReferrer;

        uint256 expiredTime = packageTimes[_packageId];
        require(expiredTime > 0, "Buy package wrong: with expiredTime");
        userPackageTimes[msg.sender] = block.timestamp + expiredTime;
        userPackageId[msg.sender] = _packageId;

        emit BuyPackage(msg.sender, _packageId, amount, referrer, amountForReferrer);
    }

    function getUserPackageId(address _account) public view returns (uint256) {
        if (userPackageTimes[_account] >= block.timestamp) {
            return userPackageId[_account];
        } else {
            return 0;
        }
    }

    function getUserLevel(address _account) public view returns (uint256) {
        uint256 balance = balanceHelper.getUserBalance(_account);

        // has buy package
        if (userPackageTimes[_account] >= block.timestamp) {
            return 5;
        }

        // fixed buy admin
        if (userLevelFixed[_account] > 0) {
            return userLevelFixed[_account];
        }
        
        if (balance < userLevel[1]) {
            return 0;
        } else if (balance < userLevel[2]) {
            return 1;
        } else if (balance < userLevel[3]) {
            return 2;
        } else if (balance < userLevel[4]) {
            return 3;
        } else if (balance < userLevel[5]) {
            return 4;
        } else {
            return 5;
        }
    }

    function getTraderLevel(address _account) public view returns (uint256) {
        uint256 balance = balanceHelper.getTraderBalance(_account);

        // fixed buy admin
        if (traderLevelFixed[_account] > 0) {
            return traderLevelFixed[_account];
        }
        
        if (balance < traderLevel[1]) {
            return 0;
        } else if (balance < traderLevel[2]) {
            return 1;
        } else if (balance < traderLevel[3]) {
            return 2;
        } else if (balance < traderLevel[4]) {
            return 3;
        } else if (balance < traderLevel[5]) {
            return 4;
        } else {
            return 5;
        }
    }

    function getRefLevel(address _account) public view returns (uint256) {
        uint256 balance = balanceHelper.getRefBalance(_account);

        // fixed buy admin
        if (refLevelFixed[_account] > 0) {
            return refLevelFixed[_account];
        }
        
        if (balance < refLevel[1]) {
            return 0;
        } else if (balance < refLevel[2]) {
            return 1;
        } else if (balance < refLevel[3]) {
            return 2;
        } else if (balance < refLevel[4]) {
            return 3;
        } else if (balance < refLevel[5]) {
            return 4;
        } else {
            return 5;
        }
    }

    /**
     * @notice Claim pending revenue
     */
    function claimPendingRevenue(address _token) external nonReentrant {
        uint256 revenueToClaim = pendingRevenue[msg.sender][_token];
        require(revenueToClaim != 0, "Claim: Nothing to claim");
        pendingRevenue[msg.sender][_token] = 0;

        IERC20(_token).safeTransfer(address(msg.sender), revenueToClaim);

        emit RevenueClaim(msg.sender, revenueToClaim);
    }
}
