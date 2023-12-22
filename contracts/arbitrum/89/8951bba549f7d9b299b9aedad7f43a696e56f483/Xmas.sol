// SPDX-License-Identifier: MIT

/*
    Discord...Ho Ho Hooo🎅🏻-> https://discord.gg/tBW2tHYPjn
    Telegram… Ho Ho Hooo🎅🏻 -> https://t.me/+n8zSDItufNwxNWQ0
    Twitter...Ho Ho Hooo🎅🏻 -> https://twitter.com/SantaClausSG
*/

interface ISushiswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface ISushiswapV2Router02 {
    function factory() external pure returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );
}

pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./ERC20.sol";
import "./Ownable.sol";

contract Xmas is ERC20, Ownable {
    // maxSupply is overrided for people who wants to verify it, we know that we should have pass _maxSupply above 1_000_000_000 ethers
    uint256 maxSupply = 1_000_000_000 ether;
    uint256 maxWalletSize = 30_000_000 ether;

    // minimum of tokens to hold for airdrop
    uint256 minToHold = 10_000_000 ether;

    // wallets involved
    address public teamWallet =
        address(0xFC7d8F3b912cFf8269e7370443408B14c19d365c);
    address public treasuryWallet =
        address(0xf695AF3B0b881d8Ea0BA305d70eF5691Fb7e99C6);
    address public marketingWallet =
        address(0x4c170692301e783c545450123533d34BD8111287);
    address public giveawaysWallet =
        address(0xD636120691198BF562380a87FcD777f74AAC2887);

    address deadWallet = address(0x0000000000000000000000000000000000000000);

    // Sushi address
    address public sushiswapV2Pair;
    address public sushiRouter =
        address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    ISushiswapV2Router02 public sushiswapV2Router;

    // Sushi swap address
    address public WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // number of days for this event
    uint8 daysOfEvent = 25;
    uint256 minHolderToClaim = 20;

    // days to manage the event
    uint32 public startDay = 1669852800;
    uint32 public currentDay = 1669852800;

    uint32 public countActiveUsers = 0;
    uint256 public holders = 0;

    struct AirdropInformation {
        address owner;
        bool active;
        uint8 numberOfDays;
        uint32 lastClaim;
    }

    // mappings
    mapping(address => mapping(uint256 => bool)) activeDays;
    mapping(address => AirdropInformation) usersActivity;
    mapping(uint32 => address) allAddress;
    mapping(address => mapping(uint256 => bool)) hasClaimed;

    // fees
    uint256 public buyFees = 5;
    uint256 public sellFees = 5;

    // airdrop rate
    uint8 public airdropRate = 1;

    constructor() ERC20("XMAS", "XMAS") {
        ISushiswapV2Router02 _sushiswapV2Router = ISushiswapV2Router02(
            sushiRouter
        );
        sushiswapV2Pair = ISushiswapV2Factory(_sushiswapV2Router.factory())
            .createPair(address(this), WETH);
        IERC20(sushiswapV2Pair).approve(sushiRouter, maxSupply);
        _mint(msg.sender, 750_000_000 ether);
        _mint(giveawaysWallet, 150_000_000 ether);
        _mint(treasuryWallet, 100_000_000 ether);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        uint256 tokensCollected;
        uint256 amountWithFee;
        uint256 toTeam;
        uint256 toTreasury;
        uint256 toMarketing;
        uint256 toGiveaways;
        // on sell
        if (to == sushiswapV2Pair) {
            tokensCollected = (amount / 100) * sellFees;
            amountWithFee = amount - tokensCollected;

            toTeam = (tokensCollected / 100) * 30;
            toTreasury = (tokensCollected / 100) * 25;
            toMarketing = (tokensCollected / 100) * 15;
            toGiveaways = (tokensCollected / 100) * 30;

            super._transfer(from, to, amountWithFee);
            super._transfer(from, teamWallet, toTeam);
            super._transfer(from, treasuryWallet, toTreasury);
            super._transfer(from, marketingWallet, toMarketing);
            super._transfer(from, giveawaysWallet, toGiveaways);
        }
        // on buy
        else if (from == sushiswapV2Pair) {
            if (_holdMoreThanMaxWalletSize(to, amount))
                revert("Swap: you cannot swap more than 1% of the LP");
            tokensCollected = (amount / 100) * buyFees;
            amountWithFee = amount - tokensCollected;

            toTeam = (tokensCollected / 100) * 30;
            toTreasury = (tokensCollected / 100) * 25;
            toMarketing = (tokensCollected / 100) * 15;
            toGiveaways = (tokensCollected / 100) * 30;

            super._transfer(from, to, amountWithFee);
            super._transfer(from, teamWallet, toTeam);
            super._transfer(from, treasuryWallet, toTreasury);
            super._transfer(from, marketingWallet, toMarketing);
            super._transfer(from, giveawaysWallet, toGiveaways);
        } else {
            super._transfer(from, to, amount);
        }
    }

    function _beforeSwap(address _owner, uint256 _amount)
        internal
        view
        returns (bool)
    {
        uint256 tokenHoldByOwner = balanceOf(_owner);
        uint256 tokenPercentage = (tokenHoldByOwner + _amount / maxSupply) *
            100; // To modify => 75% would be passed to LP so it would not be totalSupply but 75% of the total supply
        return tokenPercentage < 1;
    }

    function setFees(uint256 _buyFees, uint256 _sellFees) external onlyOwner {
        require(
            _buyFees + _sellFees <= 14,
            "Fees: cannot set fees more than 14%"
        );
        buyFees = _buyFees;
        sellFees = _sellFees;
    }

    function increaseAirdropRate() external onlyOwner {
        if (airdropRate > 24)
            revert("Increase: failed to increase rate of airdrop");
        airdropRate += 1;
    }

    function changeMinToHold(uint32 _minToHold) external onlyOwner {
        minToHold = _minToHold;
    }

    function claimToken() external {
        require(
            balanceOf(msg.sender) >= minToHold,
            "You cannot claim your Xmas Tokens"
        );
        require(
            minHolderToClaim >= getTotalActiveUserOfTheDay(),
            "Need minimun holders"
        );
        if (
            activeDays[msg.sender][currentDay] &&
            !hasClaimed[msg.sender][currentDay]
        ) {
            uint256 balanceOfThis = balanceOf(address(this));
            uint256 toReceive = (balanceOfThis / getTotalActiveUserOfTheDay());
            super._transfer(address(this), msg.sender, toReceive);
            hasClaimed[msg.sender][currentDay] = true;
        } else {
            revert("you can't claim more than once per day");
        }
    }

    function setMinHolderToClaim(uint16 minHolder) external onlyOwner {
        minHolderToClaim = minHolder;
    }

    function getTotalActiveUserOfTheDay() public view returns (uint16) {
        uint32 activeUsers = countActiveUsers;
        uint16 counter = 0;
        for (uint16 i = 0; i < activeUsers; i++) {
            if (usersActivity[allAddress[i]].active) {
                counter += 1;
            }
        }
        return counter;
    }

    function getAddressesOfActiveMembersOfTheDay()
        public
        view
        returns (address[] memory)
    {
        uint16 activeUsers = getTotalActiveUserOfTheDay();
        uint16 counter = 0;
        address[] memory walletsOfTheDay = new address[](activeUsers);

        for (uint32 i = 0; i < countActiveUsers; i++) {
            if (usersActivity[allAddress[i]].active) {
                walletsOfTheDay[counter] = usersActivity[allAddress[i]].owner;
                counter++;
            }
        }
        return walletsOfTheDay;
    }

    function _holdMoreThanMaxWalletSize(address _user, uint256 _amount)
        internal
        view
        returns (bool)
    {
        return balanceOf(_user) + _amount >= maxWalletSize;
    }

    function changeMaxWalletSize(uint256 _maxWalletSize) external onlyOwner {
        maxWalletSize = _maxWalletSize;
    }

    function countActiveDaysOf(address _user) public view returns (uint8) {
        return usersActivity[_user].numberOfDays;
    }

    function imActive() external {
        require(
            balanceOf(msg.sender) > minToHold,
            "You need to hold more Xmas token on your wallet"
        );
        AirdropInformation storage airdropInformation = usersActivity[
            msg.sender
        ];
        if (usersActivity[msg.sender].owner == deadWallet) {
            allAddress[countActiveUsers] = msg.sender;
            countActiveUsers += 1;
            airdropInformation.owner = msg.sender;
            airdropInformation.active = true;
        }
        if (!activeDays[msg.sender][currentDay]) {
            airdropInformation.numberOfDays += 1;
            activeDays[msg.sender][currentDay] = true;
            hasClaimed[msg.sender][currentDay] = false;
        }
        if (oneDayElapsed()) nextDay();
    }

    function getAirdropInformation()
        external
        view
        returns (AirdropInformation memory)
    {
        return usersActivity[msg.sender];
    }

    function getActiveUser(address _user) public view returns (bool) {
        return activeDays[_user][currentDay];
    }

    function getHasClaimed(address _user) public view returns (bool) {
        return hasClaimed[_user][currentDay];
    }

    function userExist() external view returns (bool) {
        return usersActivity[msg.sender].owner != deadWallet;
    }

    function oneDayElapsed() internal view returns (bool) {
        return block.timestamp > 1 days + currentDay;
    }

    function isOneDayElapsed() external view returns (bool) {
        return oneDayElapsed();
    }

    function nextDay() public onlyOwner {
        currentDay += 1 days;
    }

    function withdraw(address _token) external onlyOwner {
        IERC20 contractToken = IERC20(_token);
        uint256 balanceOfToken = contractToken.balanceOf(address(this));

        contractToken.transferFrom(address(this), msg.sender, balanceOfToken);
    }
}

