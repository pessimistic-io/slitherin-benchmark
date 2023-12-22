// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
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

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

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
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {

        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }

    function sqrrt(uint256 a) internal pure returns (uint c) {
        if (a > 3) {
            c = a;
            uint b = add( div( a, 2), 1 );
            while (b < c) {
                c = b;
                b = div( add( div( a, b ), b), 2 );
            }
        } else if (a != 0) {
            c = 1;
        }
    }

    function percentageAmount( uint256 total_, uint8 percentage_ ) internal pure returns ( uint256 percentAmount_ ) {
        return div( mul( total_, percentage_ ), 1000 );
    }

    function substractPercentage( uint256 total_, uint8 percentageToSub_ ) internal pure returns ( uint256 result_ ) {
        return sub( total_, div( mul( total_, percentageToSub_ ), 1000 ) );
    }

    function percentageOfTotal( uint256 part_, uint256 total_ ) internal pure returns ( uint256 percent_ ) {
        return div( mul(part_, 100) , total_ );
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }

    function quadraticPricing( uint256 payment_, uint256 multiplier_ ) internal pure returns (uint256) {
        return sqrrt( mul( multiplier_, payment_ ) );
    }

  function bondingCurve( uint256 supply_, uint256 multiplier_ ) internal pure returns (uint256) {
      return mul( multiplier_, supply_ );
  }
}

interface IStore {
    function poolWithdraw(address token, address receiver, uint256 amount) external;
}

contract SecuraFarm {
    using SafeMath for uint256;

    address public _manager;
    address public constant _owner = 0xb931044c1B890A02A8dE21A3cB71AeEaC2cFF415;

    mapping(address => AggregatorV3Interface) internal priceFeedOf;

    uint256 public constant boostPro = 500000000;
    uint256 public constant generalPro = 50000000;
    
    //token addresses
    address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant LINK = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
    address public constant DPX = 0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55;
    address public constant MAGIC = 0x539bdE0d7Dbd336b79148AA742883198BBF60342;
    address public constant GMX = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;

    //native token address
    address public semo;
    
    struct depositInfo {
        uint256 amount;
        uint256 timestamp;
        uint256 apy;
    }
    mapping(address => mapping(address => depositInfo)) public depositsOf; // [owner][token]

    //apy information of token, apy decimal: 6(1000000 = 100%)
    struct apyInfo {
        bool isStable;
        uint256 initialApy;
    }
    mapping(address => apyInfo) public apyOf;

    mapping(address => uint256) public totalDepositsOf;

    address private _storeCont1;
    address private _storeCont2;

    event Deposit(address owner, address token, uint256 amount);
    event Withdraw(address owner, address token, uint256 amount);
    event ClaimRewards(address onwer, uint256 amount);

    constructor(address storeCont1, address storeCont2, address semoAddr) {
        _manager = msg.sender;
        _storeCont1= storeCont1;
        _storeCont2 = storeCont2;
        semo = semoAddr;
        apyOf[USDT] = apyInfo({
            isStable: true,
            initialApy: boostPro
        });
        apyOf[USDC] = apyInfo({
            isStable: true,
            initialApy: boostPro
        });
        apyOf[DAI] = apyInfo({
            isStable: true,
            initialApy: generalPro
        });
        apyOf[WBTC] = apyInfo({
            isStable: false,
            initialApy: generalPro
        });
        apyOf[WETH] = apyInfo({
            isStable: false,
            initialApy: generalPro
        });
        apyOf[LINK] = apyInfo({
            isStable: false,
            initialApy: generalPro
        });
        apyOf[MAGIC] = apyInfo({
            isStable: false,
            initialApy: generalPro
        });
        apyOf[DPX] = apyInfo({
            isStable: false,
            initialApy: generalPro
        });
        apyOf[GMX] = apyInfo({
            isStable: false,
            initialApy: generalPro
        });

        priceFeedOf[WBTC] = AggregatorV3Interface(0xd0C7101eACbB49F3deCcCc166d238410D6D46d57); // WBTC/USD price feed
        priceFeedOf[WETH] = AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);  // WETH/USD
        priceFeedOf[LINK] = AggregatorV3Interface(0x86E53CF1B870786351Da77A57575e79CB55812CB);  // LINK/USD
        priceFeedOf[MAGIC] = AggregatorV3Interface(0x47E55cCec6582838E173f252D08Afd8116c2202d);  // MAGIC/USD
        priceFeedOf[DPX] = AggregatorV3Interface(0xc373B9DB0707fD451Bc56bA5E9b029ba26629DF0);  // DPX/USD
        priceFeedOf[GMX] = AggregatorV3Interface(0xDB98056FecFff59D032aB628337A4887110df3dB);  // GMX/USD
    }

    modifier onlyManager() {
        require(_manager == msg.sender, "not manager");
        _;
    }

    function deposit(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        totalDepositsOf[token] = totalDepositsOf[token].add(amount);

        //In the case of already deposited amount
        if(depositsOf[msg.sender][token].amount > 0) {
            //transfer the rewards to owner
            uint256 rewardAmt = getRewards(token, msg.sender);
            depositsOf[msg.sender][token].amount = depositsOf[msg.sender][token].amount.add(amount);
            depositsOf[msg.sender][token].timestamp = block.timestamp;
            depositsOf[msg.sender][token].apy = getAPY(token);
            if(rewardAmt > 0) {
                IERC20(semo).transfer(msg.sender, rewardAmt.mul(9).div(10));
                IERC20(semo).transfer(_owner, rewardAmt.div(10));
            } 
        } else {   // In the case of first deposit
            depositsOf[msg.sender][token] = depositInfo({
            amount: amount,
            timestamp: block.timestamp,
            apy: getAPY(token)
            });
        }        
        IERC20(token).transfer(_storeCont1, amount.mul(51).div(100));
        IERC20(token).transfer(_storeCont2, amount.mul(49).div(100));
        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external {
        require(depositsOf[msg.sender][token].amount >= amount, "not enough deposit balance");
        
        //transfer the rewards to owner
        uint256 rewardAmt = getRewards(token, msg.sender);
        depositsOf[msg.sender][token].amount = depositsOf[msg.sender][token].amount.sub(amount);
        depositsOf[msg.sender][token].timestamp = block.timestamp;
        depositsOf[msg.sender][token].apy = getAPY(token);
        totalDepositsOf[token] = totalDepositsOf[token].sub(amount);
        if(rewardAmt > 0) {
            IERC20(semo).transfer(msg.sender, rewardAmt.mul(9).div(10));
            IERC20(semo).transfer(_owner, rewardAmt.div(10));
        } 

        IStore(_storeCont1).poolWithdraw(token, msg.sender, amount.mul(51).div(100));
        IStore(_storeCont2).poolWithdraw(token, msg.sender, amount.mul(49).div(100));
        emit Withdraw(msg.sender, token, amount);
    }

    function claimRewards(address token) external {
        uint256 rewardAmt = getRewards(token, msg.sender);
        depositsOf[msg.sender][token].timestamp = block.timestamp;
        depositsOf[msg.sender][token].apy = getAPY(token);
        require(rewardAmt > 0, "not claimable rewards");
        IERC20(semo).transfer(msg.sender, rewardAmt.mul(9).div(10));
        IERC20(semo).transfer(_owner, rewardAmt.div(10));
        emit ClaimRewards(msg.sender, rewardAmt);
    }

    function calculateRewards(address token, uint256 amount, uint256 userApy, uint256 firstTime, uint256 lastTime) internal view returns (uint256) {
        uint256 tokenDecimal = IERC20(token).decimals();

        //In the case of stable token
        if(apyOf[token].isStable) {
            uint256 result = userApy.mul(amount);
            result = result.div(10 ** tokenDecimal);
            result = result.mul(lastTime - firstTime).div(365 days);
            return result;
        } else {                      // In the case of non-stable token
            uint256 price = uint256(getLatestPrice(token));
            uint256 depositUSD = amount.mul(price).div(10 ** 8).div(10 ** tokenDecimal);
            uint256 result = userApy.mul(depositUSD);
            result = result.mul(lastTime - firstTime).div(365 days);
            return result;
        }
    }

    function getLatestPrice(address token) public view returns (int) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeedOf[token].latestRoundData();
        return price;
    }

    function getRewards(address token, address owner) public view returns (uint256) {
        return calculateRewards(token, depositsOf[owner][token].amount, depositsOf[owner][token].apy, depositsOf[owner][token].timestamp, block.timestamp);
    }

    function getAPY(address token) public view returns (uint256) {
        uint256 tokenDecimal = IERC20(token).decimals();
        // In the case of stable token
        if(apyOf[token].isStable) {
            uint256 totalUSD = totalDepositsOf[token].div(10 ** tokenDecimal);
            return apyOf[token].initialApy.div((100 + totalUSD).sqrrt());
        } else {  // In the case of non-stable token
            uint256 price = uint256(getLatestPrice(token));
            uint256 totalUSD = totalDepositsOf[token].mul(price).div(10 ** 8).div(10 ** tokenDecimal);
            return apyOf[token].initialApy.div((100 + totalUSD).sqrrt());
        }
    }

    function getDeposits(address token, address owner) public view returns (uint256, uint256) {
        uint256 tokenDecimal = IERC20(token).decimals();

        // In the case of stable token
        if(apyOf[token].isStable) {
            return (depositsOf[owner][token].amount, depositsOf[owner][token].amount.mul(10 ** 8).div(10 ** tokenDecimal));
        } else {
            uint256 price = uint256(getLatestPrice(token));
            uint256 depositsUSD = depositsOf[owner][token].amount.mul(price).div(10 ** tokenDecimal);  // USD decimal is 8
            return (depositsOf[owner][token].amount, depositsUSD);
        }
    }

    function getTotalDeposits(address token) public view returns (uint256, uint256) {
        uint256 tokenDecimal = IERC20(token).decimals();

        // In the case of stable token
        if(apyOf[token].isStable) {
            return (totalDepositsOf[token], totalDepositsOf[token].mul(10 ** 8).div(10 ** tokenDecimal));
        } else {
            uint256 price = uint256(getLatestPrice(token));
            uint256 totalUSD = totalDepositsOf[token].mul(price).div(10 ** tokenDecimal);
            return (totalDepositsOf[token], totalUSD);
        }
    }

    function setPriceFeedOf(address token, address feed) external onlyManager {
        priceFeedOf[token] = AggregatorV3Interface(feed);
    }

    function setApyOf(address token, uint256 apy) external onlyManager {
        require(apyOf[token].initialApy > 0, "token doesn't exist");
        apyOf[token].initialApy = apy;
    }

    function addStableToken(address token, uint256 apy) external onlyManager {
        require(apyOf[token].initialApy == 0, "existing token");
        apyOf[token] = apyInfo({
            isStable: true,
            initialApy: apy
        });
    }

    function addToken(address token, uint256 apy, address feed) external onlyManager {
        require(apyOf[token].initialApy == 0, "existing token");
        apyOf[token] = apyInfo({
            isStable: false,
            initialApy: apy
        });
        priceFeedOf[token] = AggregatorV3Interface(feed);
    }

    function getGeneralData(address token) external view returns (uint256, uint256, uint256) {
        uint256 apy = getAPY(token);
        (uint256 totalDeposits, uint256 totalUSD) = getTotalDeposits(token);
        return (apy, totalDeposits, totalUSD);
    }

    function getUserData(address token, address owner) external view returns (uint256, uint256, uint256) {
        uint256 userRewards = getRewards(token, owner);
        (uint256 userDeposits, uint256 userUSD) = getDeposits(token, owner);
        return (userRewards, userDeposits, userUSD);
    }
}