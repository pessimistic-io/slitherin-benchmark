/**
 *Submitted for verification at testnet.snowtrace.io on 2023-03-16
*/

/**
 *Submitted for verification at BscScan.com on 2023-03-07
*/

pragma solidity ^0.6.0;

pragma experimental ABIEncoderV2;
// SPDX-License-Identifier: MIT

library SafeMath {
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    assert(c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    
    uint256 c = a / b;
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }

  function ceil(uint a, uint m) internal pure returns (uint r) {
    return (a + m - 1) / m * m;
  }
}

contract Owned {
    address payable public owner;
    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address payable _newOwner) public onlyOwner {
        owner = _newOwner;
        emit OwnershipTransferred(msg.sender, _newOwner);
    }
}


interface IBEP20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint256 balance);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IPresaleProxy{
   function getDeploymentFee() external returns (uint256);
   function getTokenFee() external returns (uint256);
   function getfundReciever() external returns (address);
   function getCheckSuccess() external returns (bool);
   function getLiquidityTokenAmount() external returns(uint256);
}

interface Implementer {
    function getImplementer() external view returns (address);
}

contract BSCPresale is Owned  {
    using SafeMath for uint256;
    
    bool public isPresaleOpen;
    
    address public tokenAddress;
    uint256 public tokenDecimals = 18;

    string public tokenName;
    string public tokenSymbol;
    
    uint256 public tokenRatePerEth = 60000000000;
    uint256 public tokenRatePerEthPancake = 100;
    uint256 public rateDecimals = 0;
    
    uint256 public minEthLimit = 1e17; // 0.1 BNB
    uint256 public maxEthLimit = 10e18; // 10 BNB

    address public PROXY;
    
   
    string[] public social;
    string public description;
    string public logo;
    
    uint256 public soldTokens=0;
    
    uint256 public intervalDays;
    
    uint256 public startTime;
    
    uint256 public endTime = 2 days;
    
    bool public isClaimable = false;
    
    bool public isWhitelisted = false;

   bool public isSuccess = false;

    uint256 public hardCap = 0;
    
    uint256 public softCap = 0;
    
    uint256 public earnedCap =0;
    
    uint256 public totalSold = 0;

    uint256 public vestingInterval = 0;
    uint256 public vestingPercent = 0;

    uint256 public depolymentFee;
    uint256 public fee;
    uint256 public userFee;

    bool public buytype; // isBNB = true
    address public useWithToken;
    address payable public fundReciever = 0xfb6FF8258091f9646105C5c80beBfAa3F8c73FfD;
    IUniswapV2Router02 public  uniswapV2Router;
    address public uniswapV2Pair;
    
    bool public isautoAdd;
    bool public isVested;
    bool public isWithoutToken;
    bool public isToken;
    bool public LaunchpadType;
    
    uint256 public unlockOn;
    
    uint256 public liquidityPercent;

    uint256 public participants;
    
    address payable public ownerAddress;
    
    mapping(address => uint256) public usersInvestments;

    bool public checkForSuccess;

    mapping(address => mapping(address => uint256)) public whitelistedAddresses;
    
    struct User{
        uint256 actualBalance;
        uint256 balanceOf;
        uint256 lastClaimed;
        uint256 initialClaim;
    }


    mapping (address => User) public userInfo;

    uint256 public isWithoutTokenBalance = 0;

    uint256 public LiquidityTokenAmount = 0 ;

   
    
    constructor(address[] memory _addresses,uint256[] memory _values,bool[] memory _isSet,string[] memory _details) public {

        PROXY = Implementer(msg.sender).getImplementer();
        isWithoutToken = _isSet[2];
        if(!isWithoutToken){
        tokenAddress = _addresses[0];
        tokenDecimals = IBEP20(tokenAddress).decimals();
        tokenName = IBEP20(tokenAddress).name();
        tokenSymbol =  IBEP20(tokenAddress).symbol();
        }else{
            tokenName = _details[5];
            tokenSymbol = _details[6];
        }
        minEthLimit = _values[0];
        maxEthLimit = _values[1];
        tokenRatePerEth = _values[2];
        hardCap = _values[4];
        userFee = _values[12];
        softCap = _values[3];
        owner = payable(_addresses[2]);
        vestingPercent = _values[10];
        vestingInterval = _values[11];
        isVested = _isSet[1];
        isautoAdd = _isSet[0];
        isWhitelisted = _isSet[3];
        buytype = _isSet[4];
        isToken = _isSet[5];
        LaunchpadType = _isSet[6];

        if(isWithoutToken)
            isWithoutTokenBalance = hardCap.mul(tokenRatePerEth).div(10**(uint256(18).sub(tokenDecimals)));
      
        // Pancake testnet Router : 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
          IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_addresses[1]);
        // set the rest of the contract variables
        if(isautoAdd && !isWithoutToken){
            address pair = IUniswapV2Factory(_uniswapV2Router.factory()).getPair(tokenAddress, _uniswapV2Router.WETH());
            if(pair==address(0)){
                uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(tokenAddress, _uniswapV2Router.WETH());
            }else{
                uniswapV2Pair = pair;
            }
        }
        
        uniswapV2Router = _uniswapV2Router;
        tokenRatePerEthPancake = _values[5];
        unlockOn = _values[6].mul(1 days);
        buytype = _isSet[4];
        if(!_isSet[4])
        useWithToken = _addresses[3];
        
      
        startTime = _values[8];
        endTime = _values[9];
        if(startTime <= block.timestamp)
          isPresaleOpen = true;
        liquidityPercent = _values[7];
        depolymentFee = IPresaleProxy(PROXY).getDeploymentFee();
        fee = IPresaleProxy(PROXY).getTokenFee();
        ownerAddress = payable(IPresaleProxy(PROXY).getfundReciever());
        description = _details[0];
        social.push(_details[1]);
        social.push(_details[2]);
        social.push(_details[3]);
        logo = _details[4];
        social.push(_details[5]);
        social.push(_details[6]);
        social.push(_details[7]);
        social.push(_details[8]);
        social.push(_details[9]);
        social.push(_details[10]);
        social.push(_details[11]);
        
    }
    
    function startPresale(uint256 numberOfdays) external onlyOwner{
        startTime = block.timestamp;
        intervalDays = numberOfdays.mul(1 days);
        endTime = block.timestamp.add(intervalDays);
        isPresaleOpen = true;
        isClaimable = false;
    }

    struct Project{
        string name;
        string symbol;
        uint256 decimals;
        address tokenAddress;
        string[] social;
        string description;
        uint256 presaleRate;
        uint256 pancakeRate;
        uint256 hardCap;
        // uint256 userFee;
        uint256 softCap;
        bool isWhitelisted;
        bool isWithoutToken;
        bool buytype;
        bool isToken;
        uint256 earnedCap;
        uint256 participants;
        string logo;
        uint256 startTime;
        uint256 endTime;
        bool isVested;
        bool isPancake;
        uint256 vestingInterval;
        uint256 vestingPercent;
        uint256 minEthLimit;
        uint256 maxEthLimit;
        address owner;
        uint256 lpUnlockon;
        bool isClaimable;
        bool isPresaleOpen;
        address saleAddress;
        bool LaunchpadType;
        address useWithToken;
        uint256 liquidityPercent;
       
    }


    function getSaleInfo() public view returns (Project memory){
        return Project({
            name : tokenName,
            symbol: tokenSymbol,
            decimals: tokenDecimals,
            tokenAddress: tokenAddress,
            social: social,
            description: description,
            presaleRate: tokenRatePerEth,
            pancakeRate: tokenRatePerEthPancake,
            hardCap: hardCap,
            // userFee:userFee,
            softCap: softCap,
            isWhitelisted: isWhitelisted,
            isWithoutToken: isWithoutToken,
            buytype : buytype,
            isToken : isToken,
            earnedCap: earnedCap,
            participants: participants,
            logo: logo,
            startTime: startTime,
            endTime: endTime,
            isVested: isVested,
            isPancake: isautoAdd,
            vestingPercent: vestingPercent,
            vestingInterval: vestingInterval,
            minEthLimit: minEthLimit,
            maxEthLimit: maxEthLimit,
            owner: owner,
            lpUnlockon: unlockOn,
            isClaimable: isClaimable,
            isPresaleOpen: block.timestamp >= startTime && block.timestamp <= endTime && earnedCap <= hardCap,
            saleAddress: address(this),
            LaunchpadType:LaunchpadType,
            useWithToken:useWithToken,
            liquidityPercent:liquidityPercent

        });
    }

    struct UserInfo{
        uint256 bnbBalance;
        uint256 userInvested;
        uint256 userClaimbale;
        uint256 userWhitelistedAmount;
        uint256 userTokenBalance;
        uint256 unSoldTokens;
        uint256 initialClaim;
        uint256 actualBalance;
    }

    function getUserInfo(address user) public view returns (UserInfo memory){
        return UserInfo({
            bnbBalance: address(user).balance,
            userInvested: getUserInvestments(user),
            userClaimbale: getUserClaimbale(user),
            userWhitelistedAmount: whitelistedAddresses[tokenAddress][user],
            userTokenBalance: isWithoutToken ? 0 : IBEP20(tokenAddress).balanceOf(user),
            unSoldTokens: getUnsoldTokensBalance(),
            initialClaim: userInfo[user].initialClaim,
            actualBalance: userInfo[user].actualBalance
        });
    }

    function setVestingInfo(bool _isVest,uint256 _vestingInterval,uint256 _vestPercentage) external onlyOwner {
        isVested = _isVest;
        vestingInterval = _vestingInterval;
        vestingPercent = _vestPercentage;
    }

    function setPancakeInfo(bool _isPancake,uint256 _pancakeRate,uint256 _liquidityPercentage,uint256 _isLockedon) external onlyOwner {
        isautoAdd = _isPancake;
        tokenRatePerEthPancake = _pancakeRate;
        liquidityPercent = _liquidityPercentage;
        unlockOn = _isLockedon;
    }

    function setWhitelist(bool _value) external onlyOwner{
        isWhitelisted = _value;
    }

     function updateTokenInfo(string[] memory _info) external onlyOwner {
        description = _info[0];
        social[0]=(_info[1]);
        social[1]=(_info[2]);
        social[2]=(_info[3]);
        logo = _info[4];
    }
    
    function closePresale() external onlyOwner{
      
        totalSold = totalSold.add(soldTokens);
        endTime = block.timestamp;
        soldTokens = 0;
        isPresaleOpen = false;
    }
    
    function setTokenAddress(address token) external onlyOwner {
        tokenAddress = token;
    }
    
    function setTokenDecimals(uint256 decimals) external onlyOwner {
       tokenDecimals = decimals;
    }
    
    function setMinEthLimit(uint256 amount) external onlyOwner {
        minEthLimit = amount;    
    }
    
    function setMaxEthLimit(uint256 amount) external onlyOwner {
        maxEthLimit = amount;    
    }
    
    function setTokenRatePerEth(uint256 rate) external onlyOwner {
        tokenRatePerEth = rate;
    }
    
    function setRateDecimals(uint256 decimals) external onlyOwner {
        rateDecimals = decimals;
    }
    
    function getUserInvestments(address user) public view returns (uint256){
        return usersInvestments[user];
    }

    function addWhitelistedAddress(address _address, uint256 _allocation) external onlyOwner {
        whitelistedAddresses[tokenAddress][_address] = _allocation;
    }
            
    function addMultipleWhitelistedAddresses(address[] calldata _addresses, uint256[] calldata _allocation) external onlyOwner {
        isWhitelisted = true;
        for (uint i=0; i<_addresses.length; i++) {
            whitelistedAddresses[tokenAddress][_addresses[i]] = _allocation[i];
        }
    }

    function removeWhitelistedAddress(address _address) external onlyOwner {
        whitelistedAddresses[tokenAddress][_address] = 0;
    }    
    
    function getUserClaimbale(address user) public view returns (uint256){
        return userInfo[user].balanceOf;
    }
    
function contribute(uint256 buyamount) public payable{
    uint256 value =  !buytype ? buyamount : msg.value;
    uint256 collectfee = userFee / value * 100;
    uint256 amount = value - collectfee;
    if(buytype){
       
          payable(fundReciever).transfer(collectfee);

    }else{
        // transferFrom
        require(IBEP20(useWithToken).transferFrom(msg.sender,address(this),buyamount), "Insufficient Balance !");
        IBEP20(useWithToken).transfer(fundReciever,collectfee);
    }
        require(block.timestamp <= endTime, "Sale is not Active");
            
        // require(block.timestamp >= startTime && block.timestamp <= endTime, "Sale is not Active");
        isPresaleOpen = true;
        require(
                usersInvestments[msg.sender].add(amount) <= maxEthLimit
                && usersInvestments[msg.sender].add(amount) >= minEthLimit,
                "Installment Invalid."
            );
        if(usersInvestments[msg.sender] == 0)
        participants++;
         if(LaunchpadType){
         require(earnedCap.add(amount) <= hardCap,"Hard Cap Exceeds");
         }

        if(isWhitelisted){
            require(whitelistedAddresses[tokenAddress][msg.sender] > 0, "you are not whitelisted");
            require(whitelistedAddresses[tokenAddress][msg.sender] >= amount, "amount too high");
            require(usersInvestments[msg.sender].add(amount) <= whitelistedAddresses[tokenAddress][msg.sender], "Maximum purchase cap hit");
            whitelistedAddresses[tokenAddress][msg.sender] = whitelistedAddresses[tokenAddress][msg.sender].sub(amount);
        }
       
        if(isWithoutToken){
        require((isWithoutTokenBalance).sub(soldTokens) > 0 ,"No Presale Funds left");
        uint256 tokenAmount = getTokensPerEth(amount);
        require( (isWithoutTokenBalance).sub(soldTokens) >= tokenAmount ,"No Presale Funds left");
        userInfo[msg.sender].balanceOf = userInfo[msg.sender].balanceOf.add(tokenAmount);
        userInfo[msg.sender].actualBalance = userInfo[msg.sender].balanceOf;
        soldTokens = soldTokens.add(tokenAmount);
        usersInvestments[msg.sender] = usersInvestments[msg.sender].add(amount);
        earnedCap = earnedCap.add(amount);
        }else if(!LaunchpadType){

         usersInvestments[msg.sender] = usersInvestments[msg.sender].add(amount);
         earnedCap = earnedCap.add(amount);
       }
       else{
        require( (IBEP20(tokenAddress).balanceOf(address(this))).sub(soldTokens) > 0 ,"No Presale Funds left");
        uint256 tokenAmount = getTokensPerEth(amount);
        require( (IBEP20(tokenAddress).balanceOf(address(this))).sub(soldTokens) >= tokenAmount ,"No Presale Funds left");
        userInfo[msg.sender].balanceOf = userInfo[msg.sender].balanceOf.add(tokenAmount);
        userInfo[msg.sender].actualBalance = userInfo[msg.sender].balanceOf;
        soldTokens = soldTokens.add(tokenAmount);
        usersInvestments[msg.sender] = usersInvestments[msg.sender].add(amount);
        earnedCap = earnedCap.add(amount);
        }
        
       
 }   
    
  function claimTokens() public{
        address user = msg.sender;
        require(!(block.timestamp >= startTime && block.timestamp <= endTime), "Sale is Active");
       
        require(isClaimable, "You cannot claim tokens until the finalizeSale.");
        if(LaunchpadType)
        require(userInfo[user].balanceOf > 0 , "No Tokens left !");
        
        if(isSuccess){
            if(!LaunchpadType){
             uint256 tokenAmount = getTokensPerEth(usersInvestments[user]);
             userInfo[user].balanceOf = userInfo[user].balanceOf.add(tokenAmount);
             userInfo[user].actualBalance = userInfo[user].balanceOf;
             soldTokens = soldTokens.add(tokenAmount);

            }
            VestedClaim(user);
        }else{
        payable(msg.sender).transfer(usersInvestments[msg.sender]);
        IBEP20(useWithToken).transfer(msg.sender,usersInvestments[msg.sender]);
        }
       
    }

    function VestedClaim(address user) internal {
        if(isVested){
        require(block.timestamp > userInfo[user].lastClaimed.add(vestingInterval),"Vesting Interval is not reached !");
        uint256 toTransfer =  userInfo[user].actualBalance.mul(vestingPercent).div(10000);
        if(toTransfer > userInfo[user].balanceOf)
            toTransfer = userInfo[user].balanceOf;
        require(IBEP20(tokenAddress).transfer(user, toTransfer), "Insufficient balance of presale contract!");
        userInfo[user].balanceOf = userInfo[user].balanceOf.sub(toTransfer);
        userInfo[user].lastClaimed = block.timestamp;
        if(userInfo[user].initialClaim <= 0)
            userInfo[user].initialClaim = block.timestamp;
       }else{
        require(IBEP20(tokenAddress).transfer(user, userInfo[user].balanceOf), "Insufficient balance of presale contract!");
        userInfo[user].balanceOf = 0;
        }
    }

    function getVestedclaim(address user) public view returns (uint256) {
        uint256 toTransfer = userInfo[user].actualBalance.mul(vestingPercent).div(10000);
        uint256 vestedClaim = userInfo[user].balanceOf < toTransfer ? toTransfer : userInfo[user].balanceOf;
        return (userInfo[user].balanceOf == 0) ? 0 : vestedClaim ;
    }

    function isEligibletoVestedClaim(address _user) public view returns (bool) {
        return (block.timestamp > userInfo[_user].lastClaimed.add(vestingInterval));
    }

     function calculateTokenPrice(uint256 _earnedCap,uint256 _hardCap) public view returns (uint256){
        uint256 pricePerToken = _earnedCap.mul(10 ** 8) / _hardCap ; // pricePerToken
        uint256 valuePerBNB = 1 * 10 ** 8 / pricePerToken ; // valuePerBNB
        uint256 priceRate = valuePerBNB;
        return  priceRate;
    }
    
    function finalizeSale() public onlyOwner{
        require(!(block.timestamp >= startTime && block.timestamp <= endTime), "Sale is Active");
        depolymentFee = IPresaleProxy(PROXY).getDeploymentFee();
        fee = IPresaleProxy(PROXY).getTokenFee();
        checkForSuccess = IPresaleProxy(PROXY).getCheckSuccess();
        ownerAddress = payable(IPresaleProxy(PROXY).getfundReciever());
        uint256 feeAmount = earnedCap.mul(fee).div(10**20);

        // set tokenpereth
            if(!LaunchpadType){
              tokenRatePerEth = calculateTokenPrice(earnedCap,hardCap); 
              tokenRatePerEthPancake = tokenRatePerEth;
            }

        if(!isWithoutToken){
            if(earnedCap >= softCap || checkForSuccess)
                isSuccess = true;
        
            if(isSuccess && isautoAdd){
                _addLiquidityToken();
                ownerAddress.transfer(address(this).balance >= feeAmount ? feeAmount : 0); 
                if(!buytype)
                    IBEP20(useWithToken).transfer(msg.sender,feeAmount);
                require(IBEP20(tokenAddress).transfer(address(ownerAddress),totalSold.mul(fee).div(10**20)), "Insufficient balance of presale contract!");
            }
        }
        isClaimable = !(isClaimable);
    }
    
    function _addLiquidityToken() internal{
     uint256 amountInEth = earnedCap.mul(liquidityPercent).div(100);
     uint256 tokenAmount = amountInEth.mul(tokenRatePerEthPancake);
     tokenAmount = getEqualTokensDecimals(tokenAmount);
     LiquidityTokenAmount = tokenAmount;
     addLiquidity(tokenAmount,amountInEth);
     unlockOn = block.timestamp.add(unlockOn);
    }
    
    function checkTokentoAddLiquidty() public view returns(uint256) {
    uint256 contractBalance = IBEP20(tokenAddress).balanceOf(address(this)).sub(soldTokens.add(totalSold));
    uint256 amountInEth = earnedCap.mul(liquidityPercent).div(100);
    uint256 tokenAmount = amountInEth.mul(tokenRatePerEthPancake);
     tokenAmount =  tokenAmount.mul(uint256(1)).div(10**(uint256(18).sub(tokenDecimals).add(rateDecimals)));
         contractBalance = contractBalance.div(10 ** tokenDecimals);
            return (tokenAmount).sub(contractBalance);
    }
    
    function getTokensPerEth(uint256 amount) public view returns(uint256) {
        return amount.mul(tokenRatePerEth).div(
            10**(uint256(18).sub(tokenDecimals).add(rateDecimals))
            );
    }
    
    function getEqualTokensDecimals(uint256 amount) internal view returns (uint256){
        return amount.mul(uint256(1)).div(
            10**(uint256(18).sub(tokenDecimals).add(rateDecimals))
            );
    }
    
    
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
        // approve token transfer to cover all possible scenarios
         IBEP20(tokenAddress).approve(address(uniswapV2Router), tokenAmount);
        // add the liquidity
        if(buytype){
          uniswapV2Router.addLiquidityETH{value: ethAmount}(
           tokenAddress,
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
        }else{
            // add liq token to token
      IBEP20(useWithToken).approve(address(uniswapV2Router), ethAmount);
     uniswapV2Router.addLiquidity(
           tokenAddress,
           useWithToken,
            tokenAmount,
            ethAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
        }

    }
    
    
    function withdrawBNB() public onlyOwner{
        if(buytype) { require(address(this).balance > 0 , "No Funds Left"); owner.transfer(address(this).balance); }else{ IBEP20(useWithToken).transfer(msg.sender,IBEP20(useWithToken).balanceOf(address(this))); }
        
    }
    
    function getUnsoldTokensBalance() public view returns(uint256) {
        return isWithoutToken? isWithoutTokenBalance.sub(soldTokens) : (IBEP20(tokenAddress).balanceOf(address(this))).sub(soldTokens);
    }

    function getLiquidityTokenAmount() public view returns(uint256) {
        return LiquidityTokenAmount;
    }


    function getLPtokens() external onlyOwner {
       require(!(block.timestamp >= startTime && block.timestamp <= endTime), "Sale is Active");
        require (block.timestamp > unlockOn,"Unlock Period is still on");
        IBEP20(uniswapV2Pair).transfer(owner, (IBEP20(uniswapV2Pair).balanceOf(address(this))));
    }
    
    function getUnsoldTokens() external onlyOwner {
       require(!(block.timestamp >= startTime && block.timestamp <= endTime), "Sale is Active");
        IBEP20(tokenAddress).transfer(owner, (IBEP20(tokenAddress).balanceOf(address(this))));
    }
}

contract Implementation is Owned{
address public implementer;

    constructor() public{
    }

    function setImplementer(address _implement) public onlyOwner{
        implementer = _implement;
    }

    function getImplementer() external view returns (address){
        return implementer;
    }

    function deployProxy(address[] calldata _addresses,uint256[] calldata _values,bool[] memory _isSet,string[] memory _details) external returns (address) {
        require(msg.sender == implementer, "Proxy Falied");
         address _saleAddress = address(new BSCPresale(_addresses,_values,_isSet,_details));
         return _saleAddress;
    }
     
}