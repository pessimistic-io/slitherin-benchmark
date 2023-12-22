//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IPBOOK.sol";

// Website: https://arbitrumbook.io
// Twitter: https://twitter.com/ArbitrumBook
// Documentation: https://docs.arbitrumbook.io

//                                    %&&&/
//                                .&&&&&&&&&&/
//                             &&&&&&%%%%%%%&&&&/
//                         &&&&&&%%%%%%%%%%%%%%&&&%*
//                     *%%%&&%%%%%%%%%%%%%%%%%%%%%%%%%,
//                  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%&,
//              &&&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#&&&&.
//          #&&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%########&&&&.
//       &&&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%###############&&&&
//   &&&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#%#%############&&&&&&
//   &&&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#########&&&&&&//
//   &&&&*&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%###%&&&&&#////**
//   &&&..,,/&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%&&&////*****@
//   &&&&...,,*/%%%%%%%%%%%%%#####%%%%%%%%%%%%%%%%***/*****%&&&@@@@
//   &&&&&&%..,,**/%%%%%%#############%%%&&&&&**********&&&@@@@@@
//      &&&&%%%,,,,**/&&&&##########%&&&&&&(((#********@@@@@@
//         &&&&%%%,,,**/(&&&&####&&&&&&////**/(((**####@@.
//            &&&&%%&,,***/(&&&&&&&(///*****/&&&@######
//               &&&&&&&****///%////*****&&&@@@@@######
//                  @&@@&&&**********&&&@@@@@@   ##%%%%
//                     @@@@&&&***(&&&@@@@@(      %%%%%%
//                        @@@@&&&@@@@@@          %%%%%%
//                           @@@@@@              %

contract ArbitrumBookDynamicPresale is Ownable {
    // Total number of whitelist spots
    uint256 public constant WHITELIST_SPOTS = 130;

    // Maximum deposit per whitelisted user
    uint256 public constant MAX_DEPOSIT = 2000 * 10 ** 6;

    // Price to subscribe to the queue
    uint256 public constant SUBSCRIBE_PRICE = 100 * 10 ** 6;

    // Maximum deposit per subscribed user
    uint256 public constant MAX_DEPOSIT_QUEUE = 1000 * 10 ** 6;

    // Duration of the presale
    uint256 public constant PRESALE_DURATION = 72 hours;

    // Duration of the whitelist spot
    uint256 public constant WHITELIST_DURATION = 8 hours;

    // Duration of the whitelist after having wait in queue
    uint256 public constant WHITELIST_DURATION_QUEUE = 3 hours;

    //Presale amount goal
    uint256 public constant PRESALE_GOAL = 260000 * 10 ** 6;

    // Total amount of usdc raised during the presale
    uint256 public totalRaised;

    // Total amount raised during first round
    uint256 public totalRaisedFirstRound;

    // USDC token contract
    IERC20 public USDC;

    // Presale token contract
    IPBOOK public PBOOK;

    // List of approved users for first round
    mapping(address => bool) whitelistedUsers;

    // Total number of whitelisted users
    uint256 public whitelistedCount;

    // Amount invested by each user
    mapping(address => uint256) public userInvestments;

    bool public isPresaleOpen;

    // presale start time
    uint256 public startTime;

    mapping(address => bool) public whitelistQueue;

    // Timestamp of when a user who subscribed to the queue has claimed their spot
    mapping(address => uint256) public userClaimedTimestamp;

    address[] public whitelistQueueArray;

    // Number of users who have claimed their spot
    uint256 public claimedWhitelistCount;

    // Queue length
    uint256 public whitelistQueueLength;

    constructor(address _presaleToken, address _usdcToken) {
        PBOOK = IPBOOK(_presaleToken);
        USDC = IERC20(_usdcToken);
    }

    function addUsers(address[] memory _users) public onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            whitelistedUsers[_users[i]] = true;
            whitelistedCount++;
        }
    }

    function removeUsers(address[] memory _users) public onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            whitelistedUsers[_users[i]] = false;
            whitelistedCount--;
        }
    }

    function launchPresale() public onlyOwner {
        isPresaleOpen = true;
        startTime = block.timestamp;
    }

    function buyTokens(uint256 _amount) public {
        require(isPresaleOpen, "The presale is not open");
        require(isUserWhitelisted(msg.sender), "You are not whitelisted");
        require(_amount > 0, "The investment can not be 0");

        if (!hasFirstRoundEnded()) {
            require(
                _amount <= MAX_DEPOSIT,
                "The maximum investment amount is 1000 USDC"
            );
            require(
                userInvestments[msg.sender] + _amount <= MAX_DEPOSIT,
                "The user has reached their maximum investment limit of 1000 USDC"
            );
            require(
                USDC.allowance(msg.sender, address(this)) >= _amount,
                "You didn't approved the contract to spend USDC"
            );

            SafeERC20.safeTransferFrom(
                USDC,
                msg.sender,
                address(this),
                _amount
            );
            PBOOK.mint(msg.sender, _amount);
            userInvestments[msg.sender] += _amount;
            totalRaised += _amount;
            totalRaisedFirstRound += _amount;
        } else {
            require(
                _amount <= MAX_DEPOSIT_QUEUE,
                "The maximum investment amount is 500 USDC"
            );
            require(
                userInvestments[msg.sender] + _amount <= MAX_DEPOSIT_QUEUE,
                "You have reached the maximum investment limit of 500 USDC"
            );
            require(
                USDC.allowance(msg.sender, address(this)) >= _amount,
                "You didn't approved the contract to spend USDC"
            );

            SafeERC20.safeTransferFrom(
                USDC,
                msg.sender,
                address(this),
                _amount
            );
            PBOOK.mint(msg.sender, _amount);
            userInvestments[msg.sender] += _amount;

            totalRaised += _amount;
        }
    }

    function subscribeToQueue() public {
        require(isPresaleOpen, "The presale is not open");
        require(totalRaised < PRESALE_GOAL, "Presale goal reached");
        require(whitelistQueueLength <= 500, "No more slot available");
        require(
            USDC.allowance(msg.sender, address(this)) >= SUBSCRIBE_PRICE,
            "You didn't approved the contract to spend USDC"
        );
        SafeERC20.safeTransferFrom(
            USDC,
            msg.sender,
            address(this),
            SUBSCRIBE_PRICE
        );
        whitelistQueue[msg.sender] = true;
        whitelistQueueLength++;
    }

    function claimWhitelistSpot() public {
        require(totalRaised < PRESALE_GOAL, "Presale goal reached");
        require(
            isUserInQueue(msg.sender),
            "You must subscribe to the whitelist queue before claiming a slot. Learn more on: docs.arbitrumbook.io"
        );

        uint256 tokenToSellAfterFirstRound = PRESALE_GOAL -
            totalRaisedFirstRound;

        uint256 whitelistAvailable = (tokenToSellAfterFirstRound /
            MAX_DEPOSIT_QUEUE) - claimedWhitelistCount;

        SafeERC20.safeTransfer(USDC, msg.sender, SUBSCRIBE_PRICE);
        if (whitelistAvailable > 0) {
            claimedWhitelistCount++;
            whitelistQueue[msg.sender] = false;
            whitelistQueueArray.push(msg.sender);
            userClaimedTimestamp[msg.sender] = block.timestamp;
        } else {
            address[] memory expiredSubscribers = getAllExpiredSubscribers();
            require(
                expiredSubscribers.length > 0,
                "No more whitelist available. Try later."
            );
            uint256 fundsToGive;
            for (uint256 i = 0; i < expiredSubscribers.length; i++) {
                address expiredSubscriber = expiredSubscribers[i];
                uint256 subscriberInvestmentsLeft = MAX_DEPOSIT_QUEUE -
                    userInvestments[expiredSubscriber];

                if (
                    subscriberInvestmentsLeft == MAX_DEPOSIT_QUEUE &&
                    fundsToGive == 0
                ) {
                    fundsToGive = MAX_DEPOSIT_QUEUE;
                    userInvestments[expiredSubscriber] = 0;
                    userClaimedTimestamp[expiredSubscriber] = 0;
                } else if (
                    fundsToGive + subscriberInvestmentsLeft <= MAX_DEPOSIT_QUEUE
                ) {
                    fundsToGive += subscriberInvestmentsLeft;
                    userInvestments[expiredSubscriber] = 0;
                    userClaimedTimestamp[expiredSubscriber] = 0;
                } else if (
                    fundsToGive + subscriberInvestmentsLeft > MAX_DEPOSIT_QUEUE
                ) {
                    uint256 amount = MAX_DEPOSIT_QUEUE - fundsToGive;
                    userInvestments[expiredSubscriber] -= amount;
                    fundsToGive += amount;
                }

                if (fundsToGive == MAX_DEPOSIT_QUEUE) break;
            }

            require(
                fundsToGive == MAX_DEPOSIT_QUEUE,
                "No more whitelist available. Try later."
            );

            whitelistQueue[msg.sender] = false;
            whitelistQueueArray.push(msg.sender);
            userClaimedTimestamp[msg.sender] = block.timestamp;
        }
    }

    function bootstrapTreasury(
        address _treasury,
        uint _amount
    ) public onlyOwner {
        SafeERC20.safeTransfer(USDC, _treasury, _amount);
    }

    function hasFirstRoundEnded() public view returns (bool) {
        if (startTime == 0) return false;
        return block.timestamp >= startTime + WHITELIST_DURATION;
    }

    function isUserWhitelisted(address _user) public view returns (bool) {
        if (!hasFirstRoundEnded()) {
            return whitelistedUsers[_user];
        } else {
            if (
                userClaimedTimestamp[_user] == 0 &&
                block.timestamp >=
                userClaimedTimestamp[_user] + WHITELIST_DURATION_QUEUE
            ) {
                return false;
            }

            return true;
        }
    }

    function isUserInQueue(address account) public view returns (bool) {
        return whitelistQueue[account];
    }

    function getAllExpiredSubscribers() public view returns (address[] memory) {
        uint256 expiredSubscribersCount;

        for (uint256 i = 0; i < whitelistQueueArray.length; i++) {
            address user = whitelistQueueArray[i];

            if (
                userClaimedTimestamp[user] != 0 &&
                block.timestamp >=
                userClaimedTimestamp[user] + WHITELIST_DURATION_QUEUE &&
                userInvestments[user] < MAX_DEPOSIT_QUEUE
            ) {
                expiredSubscribersCount++;
            }
        }

        address[] memory expiredSubscribers = new address[](
            expiredSubscribersCount
        );
        uint subscriberIndex;
        for (uint256 i = 0; i < whitelistQueueArray.length; i++) {
            address user = whitelistQueueArray[i];
            if (
                userClaimedTimestamp[user] != 0 &&
                block.timestamp >=
                userClaimedTimestamp[user] + WHITELIST_DURATION_QUEUE &&
                userInvestments[user] < MAX_DEPOSIT_QUEUE
            ) {
                expiredSubscribers[subscriberIndex] = user;
                subscriberIndex++;
            }
        }

        return expiredSubscribers;
    }

    function getNumberOfClaimableWhitelistSpot()
        external
        view
        returns (uint256)
    {
        if (!hasFirstRoundEnded() || totalRaised >= PRESALE_GOAL) {
            return 0;
        }

        uint256 tokenToSellAfterFirstRound = PRESALE_GOAL -
            totalRaisedFirstRound;

        uint256 whitelistAvailable = (tokenToSellAfterFirstRound /
            MAX_DEPOSIT_QUEUE) - claimedWhitelistCount;

        if (whitelistAvailable > 0) {
            return whitelistAvailable;
        } else {
            address[] memory expiredSubscribers = getAllExpiredSubscribers();
            if (expiredSubscribers.length < 1) {
                return 0;
            } else {
                uint256 remainingFunds;

                for (uint256 i = 0; i < expiredSubscribers.length; i++) {
                    address expiredSubscriber = expiredSubscribers[i];
                    uint256 subscriberInvestmentsLeft = MAX_DEPOSIT_QUEUE -
                        userInvestments[expiredSubscriber];

                    remainingFunds += subscriberInvestmentsLeft;
                }
                uint256 spots = uint(remainingFunds) / uint(MAX_DEPOSIT_QUEUE);

                return spots;
            }
        }
    }
}

