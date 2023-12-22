// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./Ownable.sol";

contract HDDPresale is Ownable, ReentrancyGuard {
    IERC20 public HDDToken;
    IERC20 public buyingToken;

    uint8 public constant HDD_DECIMAL = 18;
    uint8 public constant BUYING_TOKEN_DECIMAL = 6;
    uint8 public constant PRICE_DECIMAL = 10;

    uint256 public constant HARD_CAP = 380_000 * 10**HDD_DECIMAL; // hardcap 380,000 HDD

    uint256 public priceToken = 5; // 0.5 USDC
    uint256 public minDepositAmount = 50 * 10**BUYING_TOKEN_DECIMAL; // min: 50 USDC
    uint256 public maxDepositAmount = 2000 * 10**BUYING_TOKEN_DECIMAL; // max: 2,000 USDC
    uint256 public startTime = 1678975200;
    uint256 public endTime = 1679234400;

    // Total HDD token user will receive
    mapping(address => uint256) public userReceive;
    // Total USDC token user deposit
    mapping(address => uint256) public userDeposited;
    // Total HDD token user claimed
    mapping(address => uint256) public userClaimed;
    // Total HDD sold
    uint256 public totalTokenSold = 0;

    // Claim token
    uint256[] public claimableTimestamp;
    mapping(uint256 => uint256) public claimablePercents;
    mapping(address => uint256) public claimCounts;

    event TokenBuy(address user, uint256 tokens);
    event TokenClaim(address user, uint256 tokens);

    constructor(address _HDDToken, address _buyingToken) {
        HDDToken = IERC20(_HDDToken);
        buyingToken = IERC20(_buyingToken);
    }

    function buy(uint256 _amount) public nonReentrant {
        require(block.timestamp >= startTime, "The presale has not started");
        require(block.timestamp <= endTime, "The presale has ended");

        require(
            userDeposited[_msgSender()] + _amount >= minDepositAmount,
            "Below minimum amount"
        );
        require(
            userDeposited[_msgSender()] + _amount <= maxDepositAmount,
            "You have reached maximum deposit amount per user"
        );

        uint256 tokenQuantity = ((_amount / priceToken) * PRICE_DECIMAL) *
            10**(HDD_DECIMAL - BUYING_TOKEN_DECIMAL);
        require(
            totalTokenSold + tokenQuantity <= HARD_CAP,
            "Hard Cap is reached"
        );

        buyingToken.transferFrom(_msgSender(), address(this), _amount);

        userReceive[_msgSender()] += tokenQuantity;
        userDeposited[_msgSender()] += _amount;
        totalTokenSold += tokenQuantity;

        emit TokenBuy(_msgSender(), tokenQuantity);
    }

    function claim() external nonReentrant {
        uint256 userReceiveAmount = userReceive[_msgSender()];
        require(userReceiveAmount > 0, "Nothing to claim");
        require(claimableTimestamp.length > 0, "Can not claim at this time");
        require(
            block.timestamp >= claimableTimestamp[0],
            "Can not claim at this time"
        );

        uint256 startIndex = claimCounts[_msgSender()];
        require(
            startIndex < claimableTimestamp.length,
            "You have claimed all token"
        );

        uint256 tokenQuantity = 0;
        for (
            uint256 index = startIndex;
            index < claimableTimestamp.length;
            index++
        ) {
            uint256 timestamp = claimableTimestamp[index];
            if (block.timestamp >= timestamp) {
                tokenQuantity +=
                    (userReceiveAmount * claimablePercents[timestamp]) /
                    100;
                claimCounts[_msgSender()]++;
            } else {
                break;
            }
        }

        require(tokenQuantity > 0, "Token quantity is not enough to claim");
        require(
            HDDToken.transfer(_msgSender(), tokenQuantity),
            "Cannot transfer HDD token"
        );

        userClaimed[_msgSender()] += tokenQuantity;

        emit TokenClaim(_msgSender(), tokenQuantity);
    }

    function getTokenClaimable(address _buyer) public view returns (uint256) {
        uint256 userReceiveAmount = userReceive[_buyer];
        uint256 startIndex = claimCounts[_buyer];
        uint256 tokenQuantity = 0;
        for (
            uint256 index = startIndex;
            index < claimableTimestamp.length;
            index++
        ) {
            uint256 timestamp = claimableTimestamp[index];
            if (block.timestamp >= timestamp) {
                tokenQuantity +=
                    (userReceiveAmount * claimablePercents[timestamp]) /
                    100;
            } else {
                break;
            }
        }
        return tokenQuantity;
    }

    function getTokenReceive(address _buyer) public view returns (uint256) {
        require(_buyer != address(0), "Zero address");
        return userReceive[_buyer];
    }

    function getTokenDeposited(address _buyer) public view returns (uint256) {
        require(_buyer != address(0), "Zero address");
        return userDeposited[_buyer];
    }

    function setSaleInfo(
        uint256 _price,
        uint256 _minDepositAmount,
        uint256 _maxDepositAmount,
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner {
        require(
            _minDepositAmount < _maxDepositAmount,
            "Deposit amount is invalid"
        );
        require(_startTime < _endTime, "Time invalid");

        priceToken = _price;
        minDepositAmount = _minDepositAmount;
        maxDepositAmount = _maxDepositAmount;
        startTime = _startTime;
        endTime = _endTime;
    }

    function setSaleTime(uint256 _startTime, uint256 _endTime)
        external
        onlyOwner
    {
        require(_startTime < _endTime, "Time invalid");
        startTime = _startTime;
        endTime = _endTime;
    }

    function getSaleInfo()
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            priceToken,
            minDepositAmount,
            maxDepositAmount,
            startTime,
            endTime
        );
    }

    function setClaimableTimes(uint256[] memory _timestamp) external onlyOwner {
        require(_timestamp.length > 0, "Empty input");
        claimableTimestamp = _timestamp;
    }

    function setClaimablePercents(
        uint256[] memory _timestamps,
        uint256[] memory _percents
    ) external onlyOwner {
        require(_timestamps.length > 0, "Empty input");
        require(_timestamps.length == _percents.length, "Empty input");
        for (uint256 index = 0; index < _timestamps.length; index++) {
            claimablePercents[_timestamps[index]] = _percents[index];
        }
    }

    function setBuyingToken(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Zero address");
        buyingToken = IERC20(_newAddress);
    }

    function setHDDToken(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Zero address");
        HDDToken = IERC20(_newAddress);
    }

    function withdrawFunds() external onlyOwner {
        buyingToken.transfer(
            _msgSender(),
            buyingToken.balanceOf(address(this))
        );
    }

    function withdrawUnsold() external onlyOwner {
        uint256 amount = HDDToken.balanceOf(address(this)) - totalTokenSold;
        HDDToken.transfer(_msgSender(), amount);
    }
}

